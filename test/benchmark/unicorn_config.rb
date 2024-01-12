# frozen_string_literal: true

require 'multiproc_log_device'
require 'fileutils'

listen "127.0.0.1:#{ENV.fetch('UNICORN_PORT', nil)}"
preload_app true
worker_processes ENV['UNICORN_WORKERS'].to_i
default_middleware false

def setup_loggers
  if ENV.key?('MULTIPROC_LOG_DEVICE_STREAM')
    $stdout.reopen MultiprocLogDevice::StreamDevice.new(attributes: {
      pid: Process.pid,
      stream_type: 'stdout',
    })
  end
  $stdout_logger = Logger.new($stdout)
  $null_logger = Logger.new(File.new('/dev/null', 'w'))
  $socat_logger = Logger.new(Socket.unix(ENV.fetch('SOCAT_SOCKET', nil)))
end

setup_loggers
after_fork do |_server, _worker|
  setup_loggers
end
