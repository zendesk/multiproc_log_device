# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing writes messages as-is to the provided stream. It literally simply
    # calls `@stream.write(message_text)` in it's {#on_message} implementation.
    #
    # Normally this framing is selected by passing `--framing none` to the CLI.
    class NoneFraming
      # Constructs a new instance of {NoneFraming}
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
      end
    end
  end
end
