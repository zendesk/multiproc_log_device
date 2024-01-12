# frozen_string_literal: true

require './test/test_helper'

module MultiprocLogDevice
  module Collector
    describe MultiprocLogDevice::Collector::Server do
      include TestTempfileSupport
      include MockFramingSupport

      before do
        @dir = Dir.mktmpdir
        @config = Configuration.new.tap do |c|
          c.runtime_dir = @dir
          c.framing_class = NoneFraming
          c.out_stream = StringIO.new
        end
      end

      it 'runs the provided subprocess' do
        result_file = make_tempfile
        program = make_tempfile <<~RUBY
          File.open(#{result_file.dump}, 'w') do |f|
            f.write 'subprocess_has_run'
          end
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run

        assert_equal 'subprocess_has_run', File.read(result_file)
      end

      it 'does not exit until the subprocess exits' do
        pidfile = make_tempfile
        program = make_tempfile <<~RUBY
          File.open(#{pidfile.dump}, 'w') do |f|
            f.write Process.pid.to_s
          end
          sleep
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        cv = Async::Variable.new
        Sync do |root_task|
          Server.new(@config).run do
            root_task.async do |task|
              # We might need to wait for the pidfile to exist
              task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }
              pid = File.read(pidfile).chomp.to_i

              # The server should not have exited
              refute_predicate cv, :resolved?

              # Now kill the thing; the server should exit.
              Process.kill :TERM, pid

              task.with_timeout(5) { sleep 0.1 until cv.resolved? }
              assert_predicate cv, :resolved?
            end
          end
          cv.resolve
        end
      end

      it 'proxies signals to the subprocess' do
        pidfile = make_tempfile
        logfile = make_tempfile
        program = make_tempfile <<~RUBY
          Signal.trap(:INT) do
            File.write(#{logfile.dump}, 'SIGINT')
            exit
          end
          File.write(#{pidfile.dump}, Process.pid.to_s)
          sleep
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Sync do |root_task|
          server = Server.new(@config)
          server.run do
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }
              server.handle_trap :INT
            end
          end
        end

        logdata = File.read(logfile).chomp
        assert_equal 'SIGINT', logdata
      end

      def do_kill_pgroup_test(enabled)
        pidfiles = [make_tempfile, make_tempfile]
        logfiles = [make_tempfile, make_tempfile]
        program = make_tempfile <<~RUBY
          child_pid = fork do
            # Important to close stdout/stderr from the fork, because otherwise
            # the server will wait for these sockets to close
            $stdout.close
            $stderr.close
            Signal.trap(:INT) { File.write(#{logfiles[1].dump}, 'SIGINT_CHILD'); exit }
            File.write(#{pidfiles[1].dump}, Process.pid.to_s)
            # If this slept forever, it might leave orphaned children lying around if the test
            # failed for some reason
            sleep 5#{' '}
          end
          Signal.trap(:INT) { File.write(#{logfiles[0].dump}, 'SIGINT_PARENT'); exit }
          File.write(#{pidfiles[0].dump}, Process.pid.to_s)
          Process.waitpid2 child_pid
        RUBY
        @config.subcommand = [RbConfig.ruby, program]
        @config.kill_pgroup = enabled

        Sync do |root_task|
          server = Server.new(@config)
          server.run do
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while pidfiles.any? { File.empty? _1 } }
              server.handle_trap :INT
            end
          end
        end

        logfiles.map { File.read(_1).chomp }
      end

      it 'kills the entire process group in pgroup mode' do
        logdata = do_kill_pgroup_test true
        assert_equal %w[SIGINT_PARENT SIGINT_CHILD], logdata
      end

      it 'kills only the direct child in non-pgroup mode' do
        logdata = do_kill_pgroup_test false
        assert_equal ['SIGINT_PARENT', ''], logdata
      end

      it 'disconnects from the controlling terminal' do
        logfile = make_tempfile
        program = make_tempfile <<~RUBY
          begin
            File.open('/dev/tty')
          rescue StandardError => e
            File.write(#{logfile.dump}, e.class.name)
          else
            File.write(#{logfile.dump}, 'OK')
          end
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run

        assert_equal 'Errno::ENXIO', File.read(logfile).chomp
      end

      it 'returns the subprocess exit status' do
        @config.subcommand = [RbConfig.ruby, '-e', 'exit 34']
        ret = Server.new(@config).run

        assert_kind_of Process::Status, ret
        assert_equal 34, ret.exitstatus
      end

      it 'terminates the child on an unhandled exception' do
        pidfile = make_tempfile
        program = make_tempfile <<~RUBY
          File.write(#{pidfile.dump}, Process.pid.to_s)
          sleep
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        test_exception = Class.new(StandardError)
        assert_raises(test_exception) do
          Sync do |root_task|
            Server.new(@config).run do
              root_task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }
              raise test_exception, 'kaboom'
            end
          end
        end

        # This test is technically racy because of pid reuse, but.... :shrug:
        assert_raises(Errno::ESRCH) do
          Process.kill 0, File.read(pidfile).chomp.to_i
        end
      end

      it 'prints output from the invoked program' do
        @config.subcommand = [RbConfig.ruby, '-e', 'puts "hello"']
        Server.new(@config).run

        assert_equal "hello\n", @config.out_stream.string
      end

      it 'waits for open sockets to close after the subprocess exits' do
        program = make_tempfile <<~RUBY
          $stdout.sync = true
          r, w = IO.pipe
          fork do
            w.close
            r.read # Wait for parent to exit
            10.times do |i|
              puts "LOOP \#{i}"
              sleep 0.1
            end
          end
          r.close
          sleep 1
          exit
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run

        expected = 10.times.map { |i| "LOOP #{i}\n" }.join
        assert_equal expected, @config.out_stream.string
      end

      it 'applies a provided timeout on waiting for subprocess exits' do
        pidfile = make_tempfile
        program = make_tempfile <<~RUBY
          $stdout.sync = true
          r, w = IO.pipe
          fork do
            w.close
            File.write(#{pidfile.dump}, Process.pid.to_s)
            r.read # Wait for parent to exit
            puts "FIRST_MESSAGE"
            sleep 10
            puts "SECOND_MESSAGE"
          end
          r.close
          sleep#{' '}
        RUBY
        @config.subcommand = [RbConfig.ruby, program]
        @config.shutdown_timeout = 2

        cv = Async::Variable.new
        Sync do |root_task|
          Server.new(@config).run do |server|
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }
              t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              # Shut everything down...
              server.handle_trap :TERM

              # We should wait for long enough to see the first message written
              # to the socket, but not the second message.
              cv.wait
              t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              assert_operator t2 - t1, :>=, 2
              assert_operator t2 - t1, :<, 10
              assert_includes @config.out_stream.string, 'FIRST_MESSAGE'
              refute_includes @config.out_stream.string, 'SECOND_MESSAGE'
            end
          end
          cv.resolve
        end
      end

      it 'sets the MULTIPROC_LOG_DEVICE_* env variables in the child' do
        logfile = make_tempfile
        program = make_tempfile <<~RUBY
          File.write(#{logfile.dump}, ENV.fetch('MULTIPROC_LOG_DEVICE_STREAM', 'NOT_PRESENT'))
          sleep
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Sync do |root_task|
          Server.new(@config).run do |server|
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while File.empty?(logfile) }
              log_device_socket = File.read(logfile)

              refute_equal 'NOT_PRESENT', log_device_socket
              assert_predicate File.stat(log_device_socket), :socket?

              server.handle_trap :TERM
            end
          end
        end
      end

      it 'uses the provided framing' do
        program = make_tempfile <<~RUBY
          $stdout.puts "from_stdout_1"
          $stdout.puts "from_stdout_2"
        RUBY
        @config.subcommand = [RbConfig.ruby, program]
        @config.framing_class = mock_framing { |message, _attributes| "[FRAMED] #{message}" }

        Server.new(@config).run

        assert_equal <<~EXPECTED, @config.out_stream.string
          [FRAMED] from_stdout_1
          [FRAMED] from_stdout_2
        EXPECTED
      end

      it 'passes pid, stdout & stderr tags to the initial process' do
        pidfile = make_tempfile
        program = make_tempfile <<~RUBY
          File.write(#{pidfile.dump}, Process.pid)
          $stdout.puts "from_stdout_1"
          $stderr.puts "from_stderr_2"
        RUBY
        @config.subcommand = [RbConfig.ruby, program]
        @config.framing_class = mock_framing do |message, attributes|
          "[#{attributes[:stream_type].inspect}] #{message.chomp} (pid #{attributes[:pid]})\n"
        end

        Server.new(@config).run
        lines = @config.out_stream.string.chomp.split("\n")
        pid = File.read(pidfile).chomp.to_i

        assert_includes lines, "[:stdout] from_stdout_1 (pid #{pid})"
        assert_includes lines, "[:stderr] from_stderr_2 (pid #{pid})"
      end

      it 'can make new connections to the stream socket' do
        program = make_tempfile <<~RUBY
          require 'multiproc_log_device'
          new_conn = MultiprocLogDevice::StreamDevice.new(attributes: {
            custom: 'foo',
            stream_type: :special,
            bool: true,
          })
          $stdout.puts "from_stdout"
          new_conn.puts "from_special"
        RUBY
        @config.subcommand = [RbConfig.ruby, program]
        @config.framing_class = mock_framing do |message, attributes|
          "message: #{message.chomp}, " \
            "type: #{attributes[:stream_type].inspect}, " \
            "custom: #{attributes.fetch(:custom, 'nil')}\n"
        end

        status = Server.new(@config).run
        assert_predicate status, :success?
        lines = @config.out_stream.string.chomp.split("\n")

        assert_includes lines, 'message: from_stdout, type: :stdout, custom: nil'
        assert_includes lines, 'message: from_special, type: :special, custom: foo'
      end

      it 'can apply a max line length' do
        program = make_tempfile <<~RUBY
          puts 'short'
          puts 'a_very_long_line'
          puts 'also_short'
        RUBY
        @config.framing_class = mock_framing { |message, _attrs| "[FRAME]#{message.chomp}\n" }
        @config.subcommand = [RbConfig.ruby, program]
        @config.max_line_length = 10

        Server.new(@config).run
        # n.b. last line is just framing because 'also_short\n' is 11 characters
        assert_equal <<~EXPECTED, @config.out_stream.string
          [FRAME]short
          [FRAME]a_very_lon
          [FRAME]g_line
          [FRAME]also_short
          [FRAME]
        EXPECTED
      end

      it 'can receive structured datagram messages' do
        program = make_tempfile <<~RUBY
          require 'multiproc_log_device'
          structured = MultiprocLogDevice::StructuredDevice.new

          structured.write 'no_attrs'
          structured.write 'with_attrs_1', attributes: { foo: 'bar' }
          structured.write 'with_attrs_2', attributes: { foo: 'baz' }
        RUBY
        @config.framing_class = mock_framing { |message, attrs| "[foo: #{attrs.fetch(:foo, 'nil')}] #{message}\n" }
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run

        assert_equal <<~EXPECTED, @config.out_stream.string
          [foo: nil] no_attrs
          [foo: bar] with_attrs_1
          [foo: baz] with_attrs_2
        EXPECTED
      end

      it 'can receive datagrams during shutdown' do
        pidfile = make_tempfile
        program = make_tempfile <<~RUBY
          require 'multiproc_log_device'
          MultiprocLogDevice::StructuredDevice.new.write 'message_1', attributes: { foo: 'bar' }
          r, w = IO.pipe
          fork do
            w.close
            File.write(#{pidfile.dump}, Process.pid)
            r.read

            # Parent is now closing down.
            sleep 0.5#{' '}
            MultiprocLogDevice::StructuredDevice.new.write 'message_2', attributes: { foo: 'baz' }
          end
          r.close
          sleep
        RUBY
        @config.framing_class = mock_framing { |message, attrs| "[foo: #{attrs.fetch(:foo, 'nil')}] #{message}\n" }
        @config.subcommand = [RbConfig.ruby, program]

        Sync do |root_task|
          Server.new(@config).run do |server|
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }

              # Shut the parent down. It should take > 1 second and we should still see the datagram written
              # after the parent exited.
              server.handle_trap :TERM
            end
          end
        end

        assert_equal <<~EXPECTED, @config.out_stream.string
          [foo: bar] message_1
          [foo: baz] message_2
        EXPECTED
      end

      it 'can receive jumbo sized datagrams via fd passing' do
        expected = "#{'a' * (512 * 1024)}b\n"
        program = make_tempfile <<~RUBY
          require 'multiproc_log_device'
          jumbo_log_message = #{expected.dump}
          MultiprocLogDevice::StructuredDevice.new.write jumbo_log_message
        RUBY
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run

        assert_equal expected, @config.out_stream.string
      end

      it 'can receive lots of datagrams in a row' do
        expected_text = "#{'a' * 1024}\n"
        program = make_tempfile <<~RUBY
          require 'multiproc_log_device'
          MultiprocLogDevice::StructuredDevice.new.tap do |wr|
            100.times do |i|
              wr.write #{expected_text.dump}, attributes: { i: i }
            end
          end
        RUBY
        @config.framing_class = mock_framing { |message, attrs| "[i: #{attrs[:i]}] #{message.chomp}\n" }
        @config.subcommand = [RbConfig.ruby, program]

        Server.new(@config).run
        lines = @config.out_stream.string.split "\n"
        expected = 100.times.map { |i| "[i: #{i}] #{expected_text.chomp}" }
        assert_equal expected, lines
      end
    end
  end
end
