# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # This framing type turns received messages into a stream of newline-separated
    # [logfmt](https://brandur.org/logfmt) formatted messages.The written objects
    # contain all attributes of the message, and the message itself is written under
    # the `"message"` key.
    #
    # Example:
    #
    # ```
    # logfmt_framing.on_message("hello there!\n", {time: Time.now, service: 'fooservice'})
    # # => Writes to @stream:
    # # time=2023-01-12T00:03:37Z service=fooservice message="hello there!\n"
    # ``` class LogfmtFraming
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
      # @param message [String] The message text to write
      # @param attributes [Hash] Additional attributes to write with the message.
      def on_message(message, attributes)
        @stream.puts(attributes.merge({ message: message.chomp }).map do |k, v|
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
