# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This class contains the argumenmt parsing, signal handling, and other top-level concerns for the
    # exe/multiproc_log_device collector application.
    class Command
      # The main entrypoint for the exe/multiproc_log_device collector application. Calling this will perform
      # argument parsing on the provided argv array, print help if the arguments are malformed, or else start
      # the collector. The block, if provided, is called once the collector is running and the subprocess has
      # been spawned.
      #
      # @param argv [Array<String>] The arguments to parse, not including a leading program name (i.e. this
      #   expects to be passed the standard Ruby `ARGV` object)
      # @param stderr [IO] Where to write the help message, if argv is malformed or `-h` is passed
      # @yield [MultiprocLogDevice::Collector::Server] The collector server implementation, once it has
      #   finished booting up
      # @return [Integer] The exit code of the underlying subcommand which was spawned.
      def self.[](*argv, stderr: $stderr, &)
        config = Configuration.new
        did_help = false

        parser = OptionParser.new do |opts|
          opts.banner = <<~BANNER
            Usage: multiproc_log_device [options] -- SUBCOMMAND
              Invokes the application with SUBCOMMAND and collects its logs into a single, coherent \
            standard output stream.
          BANNER

          opts.on('-rFILE', '--require=FILE', <<~DESC) do |val|
            Require custom code into the collector process (useful for defining custom framing \
            classes)
          DESC
            require val
          end

          opts.on('-fFRAMING', '--framing=FRAMING', <<~DESC) do |val|
            What kind of framing to wrap stdout & stderr messages with. Options include:
                  json - Frame each line of stdout in a JSON object, like \
            '{"pid": "100", "message": "foobar"}'
                  none - Emit the raw lines of stdout from each subprocess without any framing. \
            This will make it impossible to distinguish which processe emitted the line
                  line - Like none, but ensures that every message always ends with a newline.
                  json - Wrap each line of output in a JSON object with its attributes.
                  logfmt - Wrap each line of output in a logfmt formatting.
                  Custom::Class - The name of a class which will be used to perform the framing; \
            it must respond to #on_message(message, attributes) and be loaded with a --require \
            option.
          DESC
            config.framing_class = val
          end

          opts.on('--kill-pgroup', <<~DESC) do |_val|
            When we receive signals, broadcast them to the child's entire process group, not just \
            the child process itself
          DESC
            config.kill_pgroup = true
          end

          opts.on('-lLENGTH', '--max-line-length=LENGTH', <<~DESC) do |val|
            Max line length to buffer in memory from a child process's output. Specify in bytes (also \
            accepts 'k', 'M', and 'G' suffixes).
          DESC
            config.max_line_length = ByteUnit.parse(val).convert_to(:byte).value.to_i
          end

          opts.on('-h', '--help', 'Print this help message') do
            stderr.puts parser.to_s
            did_help = true
          end
        end

        begin
          parser.parse!(argv)
        rescue OptionParser::InvalidOption => e
          stderr.puts e.message
          stderr.puts parser.to_s
          return 1
        end
        return 0 if did_help

        config.subcommand = argv

        new(config).run(&)
      end

      # Constructs a new instance of this class directly from the provided configuration, bypassing the
      # argument parsing which would be done by .[].
      #
      # @param config [MultiprocLogDevice::Collector::Configuration] The configuration object
      def initialize(config)
        @config = config
      end

      # Starts the collector application. Attaches signal handlers, and then constructs and executes
      # the underlying {MultiprocLogDevice::Collector::Server} implementation. If a block is provided,
      # it is called once the server is ready to consume logs and the subprocess has been spawned.
      #
      # @yield [MultiprocLogDevice::Collector::Server] The collector server implementation, once it has
      #   finished booting up
      # @return [Integer] The exit code of the underlying subcommand which was spawned.
      def run(&)
        @config.runtime_dir = Dir.mktmpdir
        server = Server.new(@config)
        # Register our global trap handlers here. Keeping this out of the server implementation
        # should hopefully keep that somewhat testable.
        old_handlers = {}
        Signal.list.each_key do |signame|
          # We will be generating our own SIGCHLD, don't forward it.
          # Also SIGEXIT is not a real signal.
          next if %w[EXIT CLD CHLD].include?(signame)

          old_handlers[signame] = Signal.trap(signame) { server.handle_trap(signame) }
        rescue ArgumentError, Errno::EINVAL
          # Ignore signals we can't trap
        end

        status = server.run(&)
        # server.run returns the Process::Status object for the subprocess we spawned.
        status.exitstatus
      ensure
        FileUtils.rm_rf(@config.runtime_dir) if @config.runtime_dir
        old_handlers&.each do |signame, handler|
          Signal.trap(signame, handler)
        rescue ArgumentError, Errno::EINVAL
        end
      end
    end
  end
end
