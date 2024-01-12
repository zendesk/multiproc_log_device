# frozen_string_literal: true

require 'bundler/setup'
require 'rubocop/rake_task'
require 'minitest/test_task'
require 'yard'

Minitest::TestTask.create
RuboCop::RakeTask.new

YARD::Rake::YardocTask.new do |t|
  t.files = ['lib/**/*.rb', '-', 'README.md', 'LICENSE']
  t.options = ['--output', 'doc/yard', '--markup', 'markdown']
end
