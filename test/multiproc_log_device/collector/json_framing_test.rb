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
        @framing.on_message('foo', {})
        assert_equal "{\"message\":\"foo\"}\n", @stream.string
      end

      it 'writes attributes as one compact line' do
        @framing.on_message('foo', { attr: 'val' })
        assert_equal "{\"attr\":\"val\",\"message\":\"foo\"}\n", @stream.string
      end

      it 'does not trim trailing newlines in the message' do
        @framing.on_message("foo\n", {})
        assert_equal "{\"message\":\"foo\\n\"}\n", @stream.string
      end
    end
  end
end
