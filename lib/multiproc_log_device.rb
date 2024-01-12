# frozen_string_literal: true

require 'socket'
require 'delegate'
require 'msgpack'
require 'tempfile'

module MultiprocLogDevice
  autoload :VERSION,            'multiproc_log_device/version'
  autoload :Collector,          'multiproc_log_device/collector'
  autoload :Protocol,           'multiproc_log_device/protocol'
  autoload :StreamDevice,       'multiproc_log_device/stream_device'
  autoload :StructuredDevice,   'multiproc_log_device/structured_device'
end
