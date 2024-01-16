# frozen_string_literal: true

require './test/test_helper'

module MultiprocLogDevice
  module Collector
    describe MultiprocLogDevice::Collector::LogfmtFraming do
      before do
        @stream = StringIO.new
        @framing = LogfmtFraming.new(@stream, Configuration.new)
      end

      it 'adds an implicit message key' do
        msg = Protocol::StructuredLogMessage.new(message_text: 'foo')
        @framing.on_message(msg)
        assert_equal "message=foo\n", @stream.string
      end

      it 'strips off a trailing newline on the message' do
        msg = Protocol::StructuredLogMessage.new(message_text: "foo\n")
        @framing.on_message(msg)
        assert_equal "message=foo\n", @stream.string
      end

      it 'does not strip off a non-trailing newline in the message' do
        msg = Protocol::StructuredLogMessage.new(message_text: "foo\nbar\n")
        @framing.on_message(msg)
        assert_equal "message=\"foo\\nbar\"\n", @stream.string
      end

      it 'includes string attributes' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo bar', attributes: { attr: 'val' }
        )
        @framing.on_message(msg)
        assert_equal "attr=val message=\"foo bar\"\n", @stream.string
      end

      it 'quotes keys and values with spaces' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo bar', attributes: { 'space attr' => 'val' }
        )
        @framing.on_message(msg)
        assert_equal "\"space attr\"=val message=\"foo bar\"\n", @stream.string
      end

      it 'formats hash attribute values' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo', attributes: { attr: { key: 'val' } }
        )
        @framing.on_message(msg)
        assert_equal "attr={:key=>\"val\"} message=foo\n", @stream.string
      end

      it 'formats hash attribute values with spaces' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo', attributes: { attr: { key: 'two words' } }
        )
        @framing.on_message(msg)
        assert_equal "attr=\"{:key=>\\\"two words\\\"}\" message=foo\n", @stream.string
      end

      it 'formats timestamps as iso8601' do
        t = Time.utc(2022, 1, 3, 4, 3, 6)
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo', attributes: { time: t }
        )
        @framing.on_message(msg)
        assert_equal "time=2022-01-03T04:03:06Z message=foo\n", @stream.string
      end

      it 'prints built in attributes' do
        msg = Protocol::StructuredLogMessage.new(
          message_text: 'foo bar', attributes: { attr: 'val' },
          pid: 1234
        )
        @framing.on_message(msg)
        assert_equal "_mpld.pid=1234 attr=val message=\"foo bar\"\n", @stream.string
      end
    end
  end
end
