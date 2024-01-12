# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing type turns received messages into a stream of newline-separated
    # compact (single-line) line JSON objects. The written objects contain all attributes
    # of the message, and the message itself is written under the `"message"` key.
    #
    # Example:
    #
    # ```
    # json_framing.on_message("foo\n", {foo: 'bar'})
    # # => writes to @stream:
    # # {"foo":"bar","message":"foo\n"}
    # ```
    #
    # Normally this framing is selected by passing `--framing json` to the CLI.
    class JsonFraming
      # Constructs a new instance of {JsonFraming}
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
      # @param attributes [Hash] Additional attributes to write with the message.
      def on_message(message, attributes)
        @stream.puts attributes.merge({ message: }).to_json
      end
    end
  end
end
