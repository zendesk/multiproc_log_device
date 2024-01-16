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
    # SLMsg = MultiprocLogDevice::Protocol::StructuredLogMessage
    # line_framing.on_message(SLMsg.new(message_text: "no newline"))
    # line_framing.on_message(SLMsg.new(message_text: "yes newline\n"))
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
      # @param slmessage [MultiprocLogDevice::Protocol::StructuredLogMessage]
      #   The message text and attributes to write. Note that this framing actually
      #   ignores the attributes.
      def on_message(slmessage)
        @stream.write slmessage.message_text
        @stream.write "\n" unless slmessage.message_text.ends_with?("\n")
      end
    end
  end
end
