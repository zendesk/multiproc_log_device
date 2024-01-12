# frozen_string_literal: true

require_relative 'lib/multiproc_log_device/version'

Gem::Specification.new do |s|
  s.name      = 'multiproc_log_device'
  s.version   = MultiprocLogDevice::VERSION
  s.authors   = ['KJ Tsanaktsidis']
  s.email     = ['ktsanaktsidis@zendesk.com']
  s.summary   = 'Safely log from multiple processes to a shared output stream'
  s.homepage  = 'https://github.com/zendesk/multiproc_log_device'
  s.license   = 'Apache-2.0'

  s.files         = Dir['LICENSE.txt', 'README.md', '{lib,exe}/**/*']
  s.bindir        = 'exe'
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.metadata['rubygems_mfa_required'] = 'true'

  s.required_ruby_version = '>= 3.2.0'

  # measured requires activesupport >= 5.2, but I don't want to run tests on such
  # an old version of activesupport on the quite new version of Ruby required to
  # handle Async.
  s.add_dependency 'activesupport', '>= 6.1'

  s.add_dependency 'async', '~> 2'
  s.add_dependency 'measured', '~> 2'
  s.add_dependency 'msgpack', '~> 1'
end
