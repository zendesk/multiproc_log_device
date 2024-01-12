# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This class forms the backbone of the implementation of the `multiproc_log_device` collector
    # script. It is normally constructed and run according to CLI option flags by the
    # {MultiprocLogDevice::Collector::Comamnd} class.
    class Server
      # Constructs a new instance of the {Server}.
      #
      # @param config [MultiprocLogDevice::Collector::Configuration] The configuration for this
      #   collector process.
      def initialize(config)
        @config = config
        @sigpipe_r, @sigpipe_w = IO.pipe
        @output_lock = Mutex.new
        @socket_client_tasks = Set.new
        @msgpack = Protocol::MsgpackFactory.pool(1)
        @framing = @config.framing_class.new(@config.out_stream, @config)
      end

      # @return [MultiprocLogDevice::Collector::Configuration] The configuration object that this
      #   instance was constructed with.
      attr_reader :config

      # @return [#on_message] The constructed instance of the framing class that will receive all
      #   log messages from the subprocess and its subprocesses.
      attr_reader :framing

      # This method starts the collector server, which includes
      #
      #   * Binding and listening on the unix sockets
      #   * Spawning the subprocess
      #
      # Once the subprocess has been started, the provided block, if any, is called.
      #
      # It does not return until the subprocess has complete and all connections to the stream
      # socket server have been closed (or, `config.shutdown_timeout` has passed).
      #
      # @yield [Server] This object
      # @return [Process::Status] The status of the subcommand.
      def run
        Async do |root_task|
          # Fire up the listener sockets; bind to them to make them exist on the filesystem.
          stream_socket_addr = Addrinfo.unix(
            File.join(@config.runtime_dir, 'multiproc_log_device_stream.sock'), :STREAM
          )
          dgram_socket_addr = Addrinfo.unix(
            File.join(@config.runtime_dir, 'multiproc_log_device_dgram.sock'), :DGRAM
          )
          stream_socket, dgram_socket = [stream_socket_addr, dgram_socket_addr].map do |addr|
            FileUtils.rm_f addr.unix_path
            addr.bind
          end

          socket_server_task = root_task.async do |task|
            # We must pass the root_task into run_socket_server, so that our already-connected
            # socket tasks are allowed to outlive the listener socket
            run_stream_server(task, root_task, stream_socket)
          end
          dgram_server_task = root_task.async { |task| run_dgram_server(task, root_task, dgram_socket) }

          # This task will complete when the subprocess finishes
          subprocess_pid = Async::Variable.new
          subprocess_task = root_task.async do |task|
            run_subprocess(task, stream_socket, dgram_socket, subprocess_pid)
          end

          # Wait for the child pid to be ready
          subprocess_pid.wait
          # Now that everything is set up, call the provided block, if any. The main point of
          # this is for testing.
          yield self if block_given?

          exit_status = subprocess_task.wait

          # Once the subprocess is done, it's time to clean up.
          # Shut down the listener socket, and wait for any connected clients to close.
          socket_server_task.stop
          socket_server_task.wait
          stream_socket.close

          root_task.with_timeout(@config.shutdown_timeout) do
            @socket_client_tasks.each(&:wait)
          rescue Async::TimeoutError
            # Hard shutdown any remaining sockets
            @socket_client_tasks.each do |task|
              task.stop
              task.wait
            end
          end

          # Only shut down the datagram sockets _after_ the stream sockets are closed,
          # since the stream sockets (which presumably are connected to subprocess stdout/stderr)
          # should be a good proxy for "all children have exited"
          dgram_server_task.stop
          dgram_server_task.wait
          dgram_socket.close

          exit_status
        ensure
          root_task.children.each(&:stop)
          [stream_socket, dgram_socket].compact.each do |sk|
            sk.close rescue nil
            FileUtils.rm_f sk.connect_address.unix_path rescue nil
          end
        end.wait
      end

      # This method forwards the given signal to the subprocess (or potentially the subprocess group)
      # according to the rules specified in `config`. It would normally be called from inside a
      # `Signal.trap` handler inside the {MultiprocLogDevice::Collector::Command}.
      #
      # The signal can be specified as:
      #
      # * A symbol, like `:INT` or `:SIGINT`
      # * A string, like 'INT' or 'SIGINT',
      # * A signal number
      #
      # @param signal [Integer, Symbol, String] The signal to forward
      def handle_trap(signal)
        # signalfd or such would be simpler on Linux, but for maximum portability and minimum
        # C-extension hackery, just use the self-pipe trick.
        signo = case signal
        when Symbol, String
          Signal.list.fetch signal.to_s.upcase.gsub(/^SIG/, '')
        when Integer
          signal
        else
          raise ArgumentError, "don't understand signal #{signal}"
        end

        @sigpipe_w.write_nonblock([signo].pack('C*'), exception: false)
      end

      private

      def run_subprocess(task, stream_socket, dgram_socket, subprocess_pid_future)
        # We unfortunately need to really call fork because Process.spawn doesn't have an setsid
        # option, and we want to detach the forked subcommand from the terminal.
        pid = fork do
          Process.setsid if Process.respond_to?(:setsid)
          Process.exec(
            {
              'MULTIPROC_LOG_DEVICE_STREAM' => stream_socket.connect_address.unix_path,
              'MULTIPROC_LOG_DEVICE_DGRAM' => dgram_socket.connect_address.unix_path,
            },
            *@config.subcommand,
            unsetenv_others: false,
            out: StreamDevice.new(
              path: stream_socket.connect_address.unix_path,
              attributes: {
                pid: Process.pid,
                stream_type: :stdout,
              }
            ),
            err: StreamDevice.new(
              path: stream_socket.connect_address.unix_path,
              attributes: {
                pid: Process.pid,
                stream_type: :stderr,
              }
            ),
            close_others: true
          )
        end
        sigdelegate_task = task.async do |subtask|
          run_sigdelegate(subtask, pid)
        end
        subprocess_pid_future.resolve pid

        _, status = Process.waitpid2 pid
        status
      ensure
        sigdelegate_task&.stop
        sigdelegate_task&.wait

        if pid && status.nil?
          # Need to kill our child if we got raised out of.
          Process.kill :KILL, pid
          Process.waitpid2 pid
        end
      end

      def run_sigdelegate(_task, subprocess_pid)
        loop do
          signo = @sigpipe_r.read(1).unpack1('C*')
          kill_pid = subprocess_pid
          kill_pid = -kill_pid if @config.kill_pgroup
          Process.kill Signal.signame(signo), kill_pid
        end
      end

      def run_stream_server(_task, root_task, stream_socket)
        stream_socket.listen Socket::SOMAXCONN
        loop do
          client_socket, addrinfo = stream_socket.accept
          root_task.async do |subtask|
            handle_stream_socket_client(subtask, client_socket, addrinfo)
          end
        end
      end

      def handle_stream_socket_client(task, socket, _addrinfo)
        # Guaranteed to be race free, because async guarantees that when you call task.async (in
        # run_socket_server), that the new task runs once immediately.
        @socket_client_tasks << task

        # Read the hello message out of the socket.
        # Need to actually create a new, stateful unpacker for this
        unpacker = Protocol::MsgpackFactory.unpacker(socket)
        init_msg = unpacker.to_enum.first

        # Now change to reading raw text, not msgpagk.
        # There might be data remaining in the unpacker buffer which we have to
        # kind of put back onto the socket.
        socket.ungetbyte(unpacker.buffer.to_s)
        each_line_args = []
        each_line_args << @config.max_line_length if @config.max_line_length.positive?
        socket.each_line(*each_line_args) do |line|
          @output_lock.synchronize do
            @framing.on_message(line, init_msg.attributes)
          end
        end
      ensure
        socket.close
        @socket_client_tasks.delete task
      end

      def run_dgram_server(_task, _root_task, dgram_socket)
        loop do
          message, _addrinfo, _rflags, *cmsgs = dgram_socket.recvmsg scm_rights: true
          recvd_ios = cmsgs.select { _1.cmsg_is?(:SOCKET, :RIGHTS) }.flat_map(&:unix_rights)
          handle_dgram_socket_message(message, recvd_ios)
        end
      end

      def handle_dgram_socket_message(message, recvd_ios)
        parsed_message = @msgpack.load(message)
        parsed_message = @msgpack.load(recvd_ios.first.read) if parsed_message.is_a?(Protocol::DgramAttachedFileProxy)

        @output_lock.synchronize do
          @framing.on_message(parsed_message.message, parsed_message.attributes)
        end
      ensure
        recvd_ios.each(&:close)
      end
    end
  end
end
