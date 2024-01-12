# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing writes messages as-is to the provided stream, except it also ensures
    # that they are newline terminated. This is useful if using `--max-line-length`
    # for example, because it means individual chunks of a line longer than the maximum
    # will be newline terminated and thus the following message won't wind up starting
    # in the middle of a line.
    #
    # Example:
    #
    # ```
    # line_framing.on_message("no newline", {attr: 'ignored'})
    # line_framing.on_message("yes newline\n", {attr: 'ignored'})
    # # => outputs to @stream:
    # # no newline
    # # yes newline
    # ```
    #
    # Normally this framing is selected by passing `--framing line` to the CLI.
    class LineFraming
      # Constructs a new instance of {LineFraming}
      #
      # @param stream [IO] The stream into which serialised messages will be written
      # @param _config [MultiprocLogDevice::Collector::Configuration] The collector
      #   configuration instance
      def initialize(stream, _config)
        @stream = stream
      end

      # Called by the collector process to write a message to the `stream`.
      #
      # @param message [String] The message text to write
      # @param _attributes [Hash] Additional attributes to write with the message. Note
      #   that this framing actually totally ignores these attributes.
      def on_message(message, _attributes)
        @stream.write message
        @stream.write "\n" unless message.ends_with?("\n")
      end
    end
  end
end
