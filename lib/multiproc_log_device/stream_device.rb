# frozen_string_literal: true

module MultiprocLogDevice
  # This class wraps a unix socket connection to the collector process's stream socket.
  # It acts as a delegator around the underlying `IO` object, which means it quacks in
  # every way just like a real `IO` object once constructed.
  class StreamDevice < SimpleDelegator
    # Constructs a new {StreamDevice} wrapping an `IO` connected to the stream socket
    # specified by `path`. Before returning the new device, it will handshake with
    # the collector objects and send it the provided attributes, which will become
    # associated with every log line written to this stream.
    #
    # @param path [String] The path to the unix socket to connect to; defaults to the
    #   environment variable `MULTIPROC_LOG_DEVICE_STREAM`, which is set when a process
    #   is running as a subprocess under the `multiproc_log_device` collector program.
    # @param attributes [Hash] The attributes which will become associated with every
    #   log line written into the socket.
    #
    # @note Once this method returns, the constructed `{StreamDevice}` responds to all
    #   `IO` methods, and any lines written into it will be received by the collector
    #   process.
    def initialize(path: ENV.fetch('MULTIPROC_LOG_DEVICE_STREAM'), attributes: {})
      @socket = Socket.unix(path)

      init_msg = Protocol::StreamHello.new(attributes:)
      @socket.write(Protocol::MsgpackFactory.dump(init_msg))

      super(@socket)
    end
  end
end
