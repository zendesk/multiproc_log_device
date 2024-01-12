# frozen_string_literal: true

require 'bundler/setup'

require 'async'
require 'async/condition'
require 'async/semaphore'
require 'benchmark/ips'
require 'multiproc_log_device'
require 'faraday'

ENV['UNICORN_PORT'] ||= '10782'
raise 'Set UNICORN_WORKERS to the number of worker processes you want' unless ENV.key?('UNICORN_WORKERS')

# Fire up a socat instance which pipes to /dev/null. This will let us compare the overhead of
# multiproc_log_device itself compared with just the context switching required to get to it.

tempdir = Dir.mktmpdir

ENV['SOCAT_SOCKET'] = File.join(tempdir, 'socat.sock')
socat_pid = Process.spawn('socat', "UNIX-LISTEN:#{ENV.fetch('SOCAT_SOCKET', nil)},fork", 'OPEN:/dev/null,ignoreeof')
retries_left = 100
begin
  Socket.unix(ENV.fetch('SOCAT_SOCKET', nil))
rescue StandardError
  retries_left -= 1
  if retries_left >= 0
    sleep 0.01
    retry
  end
  raise
end

configuration = MultiprocLogDevice::Collector::Configuration.new.tap do |c|
  c.out_stream = File.new('/dev/null', 'w')
  c.framing_class = :none
  c.subcommand = ['unicorn', '-c', 'unicorn_config.rb']
  c.runtime_dir = tempdir
  c.capture_stderr = false
end
collector_server = MultiprocLogDevice::Collector::Server.new(configuration)
# It's important we actually do this in a subprocess, because otherwise the benchmark
# itself is going to _seriously_ intefere with us processing logs
collector_pid = fork do
  # Normally the trap handling would be done by the Command class, but we bypassed it.,
  Signal.trap(:TERM) { collector_server.handle_trap(:TERM) }
  collector_server.run
end
at_exit do
  Process.kill :TERM, collector_pid
  Process.waitpid2 collector_pid
  Process.kill :TERM, socat_pid
  Process.waitpid2 socat_pid
  FileUtils.rm_rf tempdir
end

# Wait for the HTTP server to actually be ready
conn = Faraday.new(url: "http://127.0.0.1:#{ENV.fetch('UNICORN_PORT', nil)}")
retries_left = 100
begin
  conn.get('/ping')
rescue StandardError
  retries_left -= 1
  if retries_left >= 0
    sleep 0.01
    retry
  end
  raise
end

def run_benchmark(path, iters, semaphore, conn)
  Sync do
    remaining_tasks = iters
    cond = Async::Condition.new
    iters.times do
      semaphore.async do
        conn.get(path)
        remaining_tasks -= 1
        cond.signal
      end
    end
    cond.wait until remaining_tasks.zero?
  end
end

# Now run the benchmark.
Sync do
  puts "Running benchmark with #{ENV.fetch('UNICORN_WORKERS', nil)} unicorn workers."

  Benchmark.ips do |bm|
    bm.config time: 30, warmup: 15

    unicorn_semaphore = Async::Semaphore.new(ENV['UNICORN_WORKERS'].to_i)

    bm.item('Logging direct to /dev/null') do |iters|
      run_benchmark('/log_lots_null', iters, unicorn_semaphore, conn)
    end

    bm.item('Logging to socat') do |iters|
      run_benchmark('/log_lots_socat', iters, unicorn_semaphore, conn)
    end

    bm.item('Logging to multiproc_log_device') do |iters|
      run_benchmark('/log_lots_stdout', iters, unicorn_semaphore, conn)
    end
  end
end
