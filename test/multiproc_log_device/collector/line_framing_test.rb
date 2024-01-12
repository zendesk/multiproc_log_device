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
        @framing.on_message('foo bar', {})
        assert_equal "foo bar\n", @stream.string
      end

      it 'does not append newlines for messages that have them' do
        @framing.on_message("foo bar\n", {})
        assert_equal "foo bar\n", @stream.string
      end

      it 'ignores attributes' do
        @framing.on_message("foo bar\n", { attr: 'val' })
        assert_equal "foo bar\n", @stream.string
      end
    end
  end
end
