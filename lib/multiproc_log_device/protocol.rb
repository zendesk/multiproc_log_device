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
    # This message is sent by a {MultiprocLogDevice::StreamDevice} as soon as it connects
    # to the unix stream socket. After receiving this message, the server does not expect
    # any further msgpack-structured data; rather, it then expects raw text written by
    # the application to appeawr directly on the socket without any intermediate framing.
    # This makes it possible to simply call
    # `$stdout.reopen(MultiprocLogDevice::StreamDevice.new)` and automatically send any
    # stdout/stderr output (including from native extensions or the interpreter itself)
    # to the collector.
    StreamHello = Struct.new(:attributes, keyword_init: true)

    # This message is sent by a {MultiprocLogDevice::StructuredDevice} as the body of each
    # datagram that it sends to the unix datagram socket. It contains the message as a string
    # and the attributes as a hash, as passed to {MultiprocLogDevice::StructuredDevice#write},
    # which get serialsied as msgpack and sent to the log collector process.
    DgramMessage = Struct.new(:message, :attributes, keyword_init: true)

    # As a special case, if the serialised {DgramMessage} class is too big to send in
    # a unix datagram socket, the {MultiprocLogDevice::StructuredDevice} will _actually_
    # instead send an instance of this class in the datagram body, and instead send the
    # {DgramMessage} bytes in a file descriptor attached to the message with ancillary data.
    # Thus, this class acts as a signal to the collector to look for any file descriptors
    # passed along with the message.
    DgramAttachedFileProxy = Class.new

    # This is the instance of the `MessagePack::Factory` which knows about the custom type
    # definitions for the collector protocol.
    MsgpackFactory = MessagePack::Factory.new.tap do |factory|
      factory.register_type(0x01, Symbol)
      factory.register_type(
        0x02,
        StreamHello,
        recursive: true,
        packer: ->(msg, packer) do
          packer.write msg.attributes
        end,
        unpacker: ->(unpacker) do
          StreamHello.new.tap do |msg|
            msg.attributes = unpacker.read
          end
        end
      )
      factory.register_type(
        0x03,
        DgramMessage,
        recursive: true,
        packer: ->(msg, packer) do
          packer.write msg.message
          packer.write msg.attributes
        end,
        unpacker: ->(unpacker) do
          DgramMessage.new.tap do |msg|
            msg.message = unpacker.read
            msg.attributes = unpacker.read
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
