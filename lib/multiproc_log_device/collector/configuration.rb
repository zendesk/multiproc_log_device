# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This class encapsulates the configuration for the collector process implementation.
    # At the moment, the only way to affect this configuration is through the command-line
    # options, but in the future a Ruby-based configuration file mechanism might expose
    # this class directly.
    class Configuration
      # This map defines names which can be used as shortcuts for the built-in framing
      # classes with the `--framing` CLI option.
      DEFAULT_FRAMINGS = {
        json: 'MultiprocLogDevice::Collector::JsonFraming',
        line: 'MultiprocLogDevice::Collector::LineFraming',
        logfmt: 'MultiprocLogDevice::Collector::LogfmtFraming',
        none: 'MultiprocLogDevice::Collector::NoneFraming',
      }.freeze

      # Constructs a new Configuration instance, with the default settings.
      def initialize
        @framing_class = DEFAULT_FRAMINGS[:none]
        @kill_pgroup = false
        @framing = nil
        @runtime_dir = nil
        @subcommand = nil
        @out_stream = $stdout
        @shutdown_timeout = 10
        @max_line_length = 0
        @capture_stderr = true
      end

      # Sets the framing class to use. The framing implementation defines how the
      # collector process will wrap lines emitted from different subprocesses, such
      # that they can be differentiated from each other further downstream in a logging
      # pipeline. Normally set via the `--framing` CLI flag.
      #
      # @param val [Symbol, String, Class] The framing class to use.
      #
      #   * If a string is passed in, it will be turned into a real Class object on read
      #     from the {#framing_class} method, by using ActiveSupport's `#constantize`
      #     method.
      #   * If a symbol is passed in, it will be looked up as one of the default framing
      #     names with {DEFAULT_FRAMINGS}.
      #   * Otherwise, taken as the actual Class to use for framing.
      def framing_class=(val)
        @framing_class = case val
        when String, Symbol
          DEFAULT_FRAMINGS.fetch(val.downcase.to_sym, val)
        else
          val
        end
      end

      # Gets the framing class to use, as a real Class, regardless of how it was set.
      #
      # @return Class the class to use for framing
      def framing_class
        @framing_class = @framing_class.constantize if @framing_class.is_a?(String)
        @framing_class
      end

      # @return [String] The directory where the collector will store its sockets and
      #   other temporary data
      attr_accessor :runtime_dir

      # @return [Boolean] If set, the collector will forward signals to the entire
      #   subprocess's process _group_, not just the subprocess itself. Normally set
      #   via the `--kill-pgroup` CLI flag.
      attr_accessor :kill_pgroup

      # @return [Array<String>] The subcommand to spawn your application. Normally set
      #   as the `-- [rest arguments]` at the CLI.
      attr_accessor :subcommand

      # @return [IO] Where the combined output from all subrocesses will be written to.
      #   Defaults to `$stdout`.
      attr_accessor :out_stream

      # @return [Numeric] How long (in seconds) to wait for other stream sockets to
      #   close after the spawned subcommand exits. Defaults to 10. If all connections
      #   are not closed after this long, the collector process will exit regardless.
      attr_accessor :shutdown_timeout

      # How large (in bytes) the maximum line length which will be allowed to be buffered
      # in memory inside the collector process. If a process writes a line to a
      # `{MultiprocLogDevice::StreamDevice}` which is larger than this, the line will be
      #
      # Also note that this parameter _only_ affects {MultiprocLogDevice::StreamDevice}
      # instances, and _NOT_ {MultiprocLogDevice::StructuredDevice} instances.
      #
      # Defaults to zero, which means unlimited. Normally set by the `--max-line-lenght`
      # CLI flag.
      #
      # @return [Integer] The max line length, in bytes
      attr_accessor :max_line_length

      # @return [Boolean] If set, only the subprocess's stdout will be captured when
      #   spawned, not its stderr. Defaults to on
      attr_accessor :capture_stderr
    end
  end
end
