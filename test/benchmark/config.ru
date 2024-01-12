# frozen_string_literal: true

require 'json'
require 'rack'
require 'logger'
require 'securerandom'

module BenchmarkHandlers
  def self.log_lots_to(logger)
    100.times do
      logger.info('a' * 1024 * 128)
    end
  end

  def self.handle_log_lots_stdout(_env)
    log_lots_to $stdout_logger
    [200, { 'content-type' => 'text/plain' }, ['OK']]
  end

  def self.handle_log_lots_null(_env)
    log_lots_to $null_logger
    [200, { 'content-type' => 'text/plain' }, ['OK']]
  end

  def self.handle_log_lots_socat(_env)
    log_lots_to $socat_logger
    [200, { 'content-type' => 'text/plain' }, ['OK']]
  end

  def self.handle_log_json_null(_env)
    100.times do
      $null_logger.info(JSON.dump({ message: 'a' * 1024 * 128 }))
    end
    [200, { 'content-type' => 'text/plain' }, ['OK']]
  end

  def self.handle_ping(_env)
    [200, { 'content-type' => 'text/plain' }, ['OK']]
  end
end

benchmark_app = Rack::Builder.new do
  map '/log_lots_stdout' do
    run BenchmarkHandlers.method(:handle_log_lots_stdout)
  end
  map '/log_lots_null' do
    run BenchmarkHandlers.method(:handle_log_lots_null)
  end
  map '/log_json_null' do
    run BenchmarkHandlers.method(:handle_log_json_null)
  end
  map '/log_lots_socat' do
    run BenchmarkHandlers.method(:handle_log_lots_socat)
  end
  map '/ping' do
    run BenchmarkHandlers.method(:handle_ping)
  end
end

run benchmark_app
