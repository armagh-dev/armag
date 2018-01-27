# Copyright 2018 Noragh Analytics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'fileutils'

module Armagh
  module Utils
    class Daemonizer

      def self.run(script, app_name: 'unknown', work_dir: File.join('','tmp', app_name), suppress_stdout: true)
        @app_name = app_name
        @work_dir = work_dir
        @script = script
        @suppress_stdout = suppress_stdout

        @pid_file = File.join(@work_dir, "#{@app_name}.pid")
        @log_file = File.join(@work_dir, "#{@app_name}.log")

        FileUtils.mkdir_p @work_dir

        script_name = @script.split(/\s/)[0]
        unless File.file? script_name
          $stderr.puts "Script '#{script_name}' does not exist."
          exit 1
        end

        usage if ARGV.length != 1

        case ARGV[0]
          when 'start'
            start
          when 'stop'
            stop
          when 'restart'
            restart
          when 'status'
            status
          else
            usage
        end
      end

      private_class_method def self.usage
        $stderr.puts "#{@app_name} daemon utility\n" <<
               "  USAGE: #{$PROGRAM_NAME} (start|stop|restart|status)"
        exit 1
      end

      private_class_method def self.start
        current = locked_pid
        runnable = true

        if current
          if running? current
            puts "#{@app_name} is already running as PID #{locked_pid}"
            runnable = false
          else
            puts "A PID file exists for #{current}, which is not running.  Cleaning up"
            remove_lock
          end
        end

        if runnable
          Process.fork do
            redirect_io

            Process.daemon(nil, true)
            pid = Process.fork{exec @script}
            create_lock(pid)
            Process.detach(pid)
          end
          sleep 0.1 until new_pid = locked_pid
          sleep 1
          puts "Started #{@app_name} as PID #{new_pid}"
        end
      end

      private_class_method def self.stop
        current = locked_pid
        if current && running?(current)
          Process.kill(:INT, current)
          sleep 0.1 while running? current
          puts "Stopped #{@app_name} PID #{current}"
        else
          puts "#{@app_name} was not running"
        end
        remove_lock
      end

      private_class_method def self.restart
        stop
        start
      end

      private_class_method def self.status
        current = locked_pid
        if current
          if running?(current)
            puts "#{@app_name} is running as PID #{current}"
          else
            puts "#{@app_name} terminated unexpectedly"
            remove_lock
          end
        else
          puts "#{@app_name} is not running"
        end
      end

      private_class_method def self.locked_pid
        pid = nil
        if File.file? @pid_file
          content = File.read(@pid_file).strip
          pid = content.to_i unless content.empty?
        end
        pid
      end

      private_class_method def self.running?(pid)
        Process.getpgid(pid)
        true
      rescue Errno::ESRCH
        false
      end

      private_class_method def self.create_lock(pid)
        File.write(@pid_file, pid)
      end

      private_class_method def self.remove_lock
        File.delete @pid_file if File.file? @pid_file
      end

      private_class_method def self.redirect_io
        FileUtils.touch @log_file
        File.chmod(0644, @log_file)
        $stderr.reopen(@log_file, 'a')
        @suppress_stdout ? $stdout.reopen('/dev/null') :  $stdout.reopen($stderr)
        $stderr.sync = true
        $stdout.sync = true
      end
    end
  end
end
