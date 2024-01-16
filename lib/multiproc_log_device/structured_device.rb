# frozen_string_literal: true

module MultiprocLogDevice
  # This class wraps a unix datagram socket connection to the collector process's
  # datagram socket, and implements a msgpack-based protocol over the top of it.
  # Messages written into this device, along with their attributes, are sent
  # directly to the collector process without any splitting or such.
  #
  # Unlike {MultiprocLogDevice::StreamDevice}, this class is _NOT_ a delegator
  # which wraps the socket directly; the underlying socket is hidden behind an
  # explicit {#write} method.
  class StructuredDevice
    # The max size that we will even attempt to send into a unix datagram.
    # It doesn't matter if this is accurate; if we're wrong, it just means we try & fail to send a large
    # datagram first.
    MAX_DATAGRAM_SIZE = case RUBY_PLATFORM
    when /darwin/
      # On MacOS, it's _much_ smaller (seems to be just under 4k).
      4080
    else
      # This size came from here:
      # https://stackoverflow.com/questions/4729315/what-is-the-max-size-of-af-unix-datagram-message-in-linux
      130_688
    end

    # Constructs a new instance of {StructuredDevice}
    #
    # @param path [String] The path to the unix socket to connect to; defaults to the
    #   environment variable `MULTIPROC_LOG_DEVICE_DGRAM`, which is set when a process
    #   is running as a subprocess under the `multiproc_log_device` collector program.
    def initialize(path: ENV.fetch('MULTIPROC_LOG_DEVICE_DGRAM'))
      @socket = Addrinfo.unix(path, :DGRAM).connect
      @socket.setsockopt(:SOCKET, :SO_SNDBUF, MAX_DATAGRAM_SIZE)
      @msgpack = Protocol::MsgpackFactory.pool(1)
    end

    # Writes a message into the device, which sends it to the collector process. The
    # message is sent in one atomic chunk and can be of any size; if it's too big to
    # actually fit in a unix datagram, we send it through a tempfile file descriptor
    # attached to the message.
    #
    # @param message_text [String] The text of the message to write
    # @param attributes [Hash] Any custom attributes to send along with the message;
    #   These will be seen by the framing instance on the collector side and included
    #   in the e.g. JSON or logfmt output.
    def write(message_text, attributes: {})
      # Writes data without any attributes
      dgram_message = Protocol::StructuredLogMessage.new(
        message_text:, attributes:,
        pid: Process.pid, tid: Thread.current.native_thread_id,
        stream_type: :structured
      )
      dgram_message_bytes = @msgpack.dump(dgram_message)
      if dgram_message_bytes.size > MAX_DATAGRAM_SIZE
        send_through_descriptor dgram_message_bytes
      else
        begin
          @socket.sendmsg dgram_message_bytes
        rescue Errno::EMSGSIZE, Errno::ENOBUFS
          send_through_descriptor dgram_message_bytes
        end
      end
    end

    private

    def send_through_descriptor(dgram_message_bytes)
      Tempfile.open do |f|
        f.unlink
        f.write dgram_message_bytes
        f.flush
        f.rewind

        ancdata = Socket::AncillaryData.int(:UNIX, :SOCKET, :RIGHTS, f.fileno)
        redirect_message_bytes = @msgpack.dump(Protocol::DgramAttachedFileProxy.new)
        @socket.sendmsg redirect_message_bytes, 0, nil, ancdata
      end
    end
  end
end
