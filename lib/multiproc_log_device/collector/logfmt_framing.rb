# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing type turns received messages into a stream of newline-separated
    # [logfmt](https://brandur.org/logfmt) formatted messages.The written objects
    # contain all attributes of the message, and the message itself is written under
    # the `"message"` key. Built-in attributes owned by the gem itself are emitted
    # with a `_mpld.` prefix.
    #
    # Example:
    #
    # ```
    # SLMsg = MultiprocLogDevice::Protocol::StructuredLogMessage
    # logfmt_framing.on_message(SLMsg.new(
    #   message_text: "hello there\n",
    #   attributes: {service: 'fooservice', time: Time.now},
    #   pid: 123, tid: 124, stream_type: :structured
    # ))
    # # => Writes to @stream:
    # # time=2023-01-12T00:03:37Z service=fooservice _mpld.stream_type=structured _mpld.pid=123 \
    # #   _mpld.tid=124 message="hello there!\n"
    # ```
    #
    # Normally this framing is selected by passing `--framing logfmt` to the CLI.
    class LogfmtFraming
      # Constructs a new instance of {LogfmtFraming}
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
          '_mpld.stream_type': slmessage.stream_type,
          '_mpld.pid': slmessage.pid,
          '_mpld.tid': slmessage.tid,
          **(slmessage.attributes || {}),
          message: slmessage.message_text.chomp,
        }.compact_blank
        @stream.puts(obj.map do |k, v|
          "#{logfmt_escape(k)}=#{logfmt_escape(v)}"
        end.join(' '))
      end

      private

      def logfmt_escape(value)
        case value
        when Time
          value.iso8601
        when String
          value = value.dump if value.match?(/[[:space:]]/) || value.match?(/[[:cntrl:]]/)
          value
        else
          logfmt_escape value.to_s
        end
      end
    end
  end
end
