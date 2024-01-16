# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing type turns received messages into a stream of newline-separated
    # compact (single-line) line JSON objects. The written objects contain all attributes
    # of the message, and the message itself is written under the `"message"` key.
    # The built-in attributes owned by the gem itself are emitted under a `"_mpld"` key.
    #
    # Example:
    #
    # ```
    # SLMsg = MultiprocLogDevice::Protocol::StructuredLogMessage
    # json_framing.on_message(SLMsg.new(
    #   message_text: "foo\n",
    #   attributes: {foo: 'bar'},
    #   pid: 123, tid: 124, stream_type: :structured
    # ))
    # # => writes to @stream:
    # # {"foo":"bar","message":"foo\n","_mpld":{"stream_type":"structured","pid": 123,"tid": "124"}}
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
      # @param slmessage [MultiprocLogDevice::Protocol::StructuredLogMessage]
      #   The message text and attributes to write
      def on_message(slmessage)
        obj = {
          _mpld: {
            stream_type: slmessage.stream_type,
            pid: slmessage.pid,
            tid: slmessage.tid,
          }.compact_blank,
          **(slmessage.attributes || {}),
          message: slmessage.message_text,
        }.compact_blank
        @stream.puts obj.to_json
      end
    end
  end
end
