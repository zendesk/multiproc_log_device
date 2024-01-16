# frozen_string_literal: true

require './test/test_helper'

module MultiprocLogDevice
  module Collector
    describe MultiprocLogDevice::Collector::JsonFraming do
      before do
        @stream = StringIO.new
        @framing = JsonFraming.new(@stream, Configuration.new)
      end

      it 'formats messages as json' do
        msg = Protocol::StructuredLogMessage.new(message_text: 'foo')
        @framing.on_message(msg)
        assert_equal "{\"message\":\"foo\"}\n", @stream.string
      end

      it 'writes attributes as one compact line' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo', attributes: { attr: 'val' }
        )
        @framing.on_message(msg)
        assert_equal "{\"attr\":\"val\",\"message\":\"foo\"}\n", @stream.string
      end

      it 'does not trim trailing newlines in the message' do
        msg = Protocol::StructuredLogMessage.new(message_text: "foo\n")
        @framing.on_message(msg)
        assert_equal "{\"message\":\"foo\\n\"}\n", @stream.string
      end

      it 'emits built in attributes under the _mpld key' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo', attributes: { attr: 'val' },
          pid: 1234
        )
        @framing.on_message(msg)
        assert_equal "{\"_mpld\":{\"pid\":1234},\"attr\":\"val\",\"message\":\"foo\"}\n", @stream.string
      end
    end
  end
end
