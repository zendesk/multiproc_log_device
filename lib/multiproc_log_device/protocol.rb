# frozen_string_literal: true

module MultiprocLogDevice
  # This module contains definitions for the objects which are msgpack serialised and form
  # the internal protocol for communicating between the {MultiprocLogDevice::Collector::Server}
  # instance in the collector process, and the {MultiprocLogDevice::StreamDevice} and
  # {MultiprocLogDevice::StructuredDevice} instances in application processes.
  #
  # There should be no need for application code to manually construct any of these objects
  # itself.
  module Protocol
    # This type wraps up the concept of a log message, along with any custom attributes, as
    # well as non-custom attributes emitted by the multiproc_log_device gem itself.
    # These objects are either sent directly to the collector process over a datagram socket
    # (from a {MultiprocLogDevice::StructuredDevice} instance on the client side), or
    # synthesised on the collector side from message text received on a stream socket.
    StructuredLogMessage = Struct.new(:message_text, :attributes, :pid, :tid, :stream_type, keyword_init: true)

    # This message is sent by a {MultiprocLogDevice::StreamDevice} as soon as it connects
    # to the unix stream socket. After receiving this message, the server does not expect
    # any further msgpack-structured data; rather, it then expects raw text written by
    # the application to appeawr directly on the socket without any intermediate framing.
    # This makes it possible to simply call
    # `$stdout.reopen(MultiprocLogDevice::StreamDevice.new)` and automatically send any
    # stdout/stderr output (including from native extensions or the interpreter itself)
    # to the collector.
    StreamHello = Struct.new(:attributes, :pid, :stream_type, keyword_init: true)

    # As a special case, if the serialised {StructuredLogMessage} class is too big to send in
    # a unix datagram socket, the {MultiprocLogDevice::StructuredDevice} will _actually_
    # instead send an instance of this class in the datagram body, and instead send the
    # {StructuredLogMessage} bytes in a file descriptor attached to the message with ancillary
    # data. Thus, this class acts as a signal to the collector to look for any file descriptors
    # passed along with the message.
    DgramAttachedFileProxy = Class.new

    # This is the instance of the `MessagePack::Factory` which knows about the custom type
    # definitions for the collector protocol.
    MsgpackFactory = MessagePack::Factory.new.tap do |factory|
      factory.register_type(0x01, Symbol)
      factory.register_type(
        0x02,
        StructuredLogMessage,
        recursive: true,
        packer: ->(msg, packer) do
          packer.write msg.message_text
          packer.write msg.attributes
          packer.write msg.pid
          packer.write msg.tid
          packer.write msg.stream_type
        end,
        unpacker: ->(unpacker) do
          StructuredLogMessage.new.tap do |msg|
            msg.message_text = unpacker.read
            msg.attributes = unpacker.read
            msg.pid = unpacker.read
            msg.tid = unpacker.read
            msg.stream_type = unpacker.read
          end
        end
      )
      factory.register_type(
        0x03,
        StreamHello,
        recursive: true,
        packer: ->(msg, packer) do
          packer.write msg.attributes
          packer.write msg.pid
          packer.write msg.stream_type
        end,
        unpacker: ->(unpacker) do
          StreamHello.new.tap do |msg|
            msg.attributes = unpacker.read
            msg.pid = unpacker.read
            msg.stream_type = unpacker.read
          end
        end
      )
      factory.register_type(
        0x04,
        DgramAttachedFileProxy,
        recursive: true,
        packer: ->(_msg, _packer) {},
        unpacker: ->(_unpacker) { DgramAttachedFileProxy.new }
      )
    end
  end
end
