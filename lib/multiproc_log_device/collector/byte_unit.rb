# frozen_string_literal: true

module MultiprocLogDevice
  module Collector
    # A unit system for the Measured gem which lets you specify byte sizes with
    # human-readable suffixes, like "1G" or "512 kb"
    ByteUnit = Measured.build do
      unit :byte, aliases: %i[b B]
      unit :kilobyte, aliases: %i[kb kB Kb KB k K], value: '1024 byte'
      unit :megabyte, aliases: %i[mb mB Mb MB M], value: '1024 kilobyte'
      unit :gigabyte, aliases: %i[gb gB Gb GB G], value: '1024 megabyte'
    end
  end
end
