# frozen_string_literal: true

# This is the place to require our gem deps, because this file should only be loaded
# when running exe/multiproc_log_device_collector, not in people's actual apps. The
# rest of this gem should be careful not to load extraneous stuff.

require 'active_support/all'
require 'async'
require 'async/barrier'
require 'async/variable'
require 'fileutils'
require 'json'
require 'measured/base'
require 'optparse'
require 'time'
require 'socket'
require 'tmpdir'

module MultiprocLogDevice
  # This module contains the implementation of the collector, used to drive the
  # `bin/multiproc_log_device` wrapper process. None of this code should be loaded
  # into application processes which just want to send their logs _to_ the collector
  # (hence, the extensive use of `autoload`)
  module Collector
    autoload :ByteUnit,       'multiproc_log_device/collector/byte_unit'
    autoload :Command,        'multiproc_log_device/collector/command'
    autoload :Configuration,  'multiproc_log_device/collector/configuration'
    autoload :JsonFraming,    'multiproc_log_device/collector/json_framing'
    autoload :LineFraming,    'multiproc_log_device/collector/line_framing'
    autoload :LogfmtFraming,  'multiproc_log_device/collector/logfmt_framing'
    autoload :NoneFraming,    'multiproc_log_device/collector/none_framing'
    autoload :Server,         'multiproc_log_device/collector/server'
  end
end
