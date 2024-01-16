# frozen_string_literal: true

require './test/test_helper'

module MultiprocLogDevice
  module Collector
    describe MultiprocLogDevice::Collector::LineFraming do
      before do
        @stream = StringIO.new
        @framing = LineFraming.new(@stream, Configuration.new)
      end

      it 'appends newlines for messages without them' do
        msg = Protocol::StructuredLogMessage.new(message_text: 'foo bar')
        @framing.on_message(msg)
        assert_equal "foo bar\n", @stream.string
      end

      it 'does not append newlines for messages that have them' do
        msg = Protocol::StructuredLogMessage.new(message_text: "foo bar\n")
        @framing.on_message(msg)
        assert_equal "foo bar\n", @stream.string
      end

      it 'ignores attributes' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: "foo bar\n", attributes: { attr: 'val' }
        )
        @framing.on_message(msg)
        assert_equal "foo bar\n", @stream.string
      end
    end
  end
end
