# frozen_string_literal: true

require './test/test_helper'

module MultiprocLogDevice
  module Collector
    class CommandTestFramingClass
      def initialize(_stream, _config); end
      def on_message(_message, _attributes); end
    end

    describe MultiprocLogDevice::Collector::Command do
      include TestTempfileSupport

      it 'returns the subcommand exit status' do
        ret = Command['--', RbConfig.ruby, '-e', 'exit 66']
        assert_equal 66, ret
      end

      it 'splats subcommand without the double-dash' do
        program = make_tempfile 'exit 67'
        ret = Command[RbConfig.ruby, program]
        assert_equal 67, ret
      end

      it 'prints help' do
        called_block = false
        mock_stderr = StringIO.new
        Command['-h', stderr: mock_stderr] { called_block = true }

        refute called_block
        assert_includes mock_stderr.string, 'Usage: multiproc_log_device'
      end

      it 'registers signal handlers to proxy signals' do
        pidfile = make_tempfile
        logfile = make_tempfile
        program = make_tempfile <<~RUBY
          Signal.trap(:USR1) do
            File.write(#{logfile.dump}, 'SIGUSR1')
            exit
          end
          File.write(#{pidfile.dump}, Process.pid.to_s)
          sleep
        RUBY

        Sync do |root_task|
          Command['--', RbConfig.ruby, program] do
            root_task.async do |task|
              task.with_timeout(5) { sleep 0.1 while File.empty?(pidfile) }
              Process.kill :USR1, Process.pid
            end
          end
        end

        assert_equal 'SIGUSR1', File.read(logfile).chomp
      end

      it 'defaults to non-kill-pgroup mode' do
        Command['--', RbConfig.ruby, '-e', 'exit'] do |server|
          refute server.config.kill_pgroup
        end
      end

      it 'can set kill-pgroup mode' do
        Command['--kill-pgroup', '--', RbConfig.ruby, '-e', 'exit'] do |server|
          assert server.config.kill_pgroup
        end
      end

      it 'configures the framing class' do
        Command[
          '--framing', 'MultiprocLogDevice::Collector::CommandTestFramingClass',
          '--', RbConfig.ruby, '-e', 'exit'
        ] do |server|
          assert_kind_of MultiprocLogDevice::Collector::CommandTestFramingClass, server.framing
        end
      end

      it 'can require files' do
        constname = "CONST_#{SecureRandom.hex}"
        temp_ruby_file = make_tempfile "#{constname} = Object.new", ext: '.rb'
        temp_ruby_dir = File.dirname(temp_ruby_file)
        temp_ruby_feature = File.basename(temp_ruby_file, '.rb')
        $LOAD_PATH.unshift temp_ruby_dir

        refute Object.const_defined?(constname)
        Command['--require', temp_ruby_feature, '--', RbConfig.ruby, '-e', 'exit'] do
          assert Object.const_defined?(constname)
        end
      ensure
        $LOAD_PATH.delete(temp_ruby_dir) if temp_ruby_dir
      end

      it 'can set max line length' do
        Command['--max-line-length', '8M', '--', RbConfig.ruby, '-e', 'exit'] do |server|
          assert_equal(8 * 1024 * 1024, server.config.max_line_length)
        end
      end

      it 'can set json framing' do
        IO.popen('-') do |pipe|
          if pipe
            # parent
            data = JSON.parse(pipe.read)
            assert_equal "hello\n", data['message']
            assert_equal 'stdout', data['_mpld']['stream_type']
            assert data['_mpld'].key?('pid')
          else
            # child
            exit Command['--framing', 'json', '--', RbConfig.ruby, '-e', 'puts "hello"']
          end
        end
      end
    end
  end
end
