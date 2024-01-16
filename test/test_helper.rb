# frozen_string_literal: true

# Disable annoying warnings about IO::Buffer
Warning[:experimental] = false

require 'bundler/setup'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'multiproc_log_device'

require 'async'
require 'async/variable'
require 'minitest/spec'
require 'minitest/autorun'
require 'rbconfig'
require 'tempfile'
require 'timeout'

module TestTempfileSupport
  def setup
    super
    @test_tempfiles = []
  end

  def teardown
    @test_tempfiles.each(&:unlink)
    super
  end

  def make_tempfile(file_text = nil, ext: '')
    tf = Tempfile.new ['', ext]
    @test_tempfiles << tf
    tf.write(file_text) if file_text
    tf.close
    tf.path
  end
end

module MockFramingSupport
  def mock_framing(&block)
    Class.new do
      @block = block
      def self._block = @block

      def initialize(stream, _config)
        @stream = stream
      end

      def on_message(slmessage)
        @stream.write self.class._block.call(slmessage)
      end
    end
  end
end
