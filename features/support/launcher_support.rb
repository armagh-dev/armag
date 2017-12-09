# Copyright 2017 Noragh Analytics, Inc.
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

require 'sys/proctable'

module LauncherSupport

  unless defined? EXEC_NAME
    EXEC_NAME = 'armagh-agents'
    DAEMON_NAME = 'armagh-agentsd'
    AGENT_PREFIX = 'armagh-agent-'

    EXEC = File.join(File.dirname(__FILE__), '..', '..', 'bin', EXEC_NAME)
    DAEMON = File.join(File.dirname(__FILE__), '..', '..', 'bin', DAEMON_NAME)
  end

  def self.start_launcher_daemon
    `#{DAEMON} start > /dev/null`
    sleep 5
  end

  def self.stop_launcher_daemon
    `#{DAEMON} stop > /dev/null`
  end

  def self.restart_launcher_daemon
    `#{DAEMON} restart > /dev/null`
    sleep 5
  end

  def self.launch_launcher
    pid = Process.spawn("#{EXEC} 2>&1 > /dev/null")
    Process.detach(pid)
    sleep 1

    pid
  end

  def self.running?(pid)
    Process.getpgid( pid )
    true
  rescue Errno::ESRCH
    false
  end

  def self.get_agent_processes
    processes = []
    Sys::ProcTable.ps do |process|
      if process.comm == 'ruby' && process.cmdline && process.cmdline.start_with?(AGENT_PREFIX)
        processes << process
      end
    end
    processes
  end

  def self.get_launcher_processes
    processes = []
    Sys::ProcTable.ps do |process|
      if process.comm == 'ruby' &&  process.cmdline &&
        (process.cmdline.include?(EXEC_NAME) || (process.cmdline.include?(DAEMON_NAME)))
        processes << process
      end
    end
    processes
  end

  def self.get_daemon_status
    `#{DAEMON} status`
  end

  def self.kill_launcher_processes
    LauncherSupport.stop_launcher_daemon

    processes = LauncherSupport.get_launcher_processes
    processes.each do |process|
      pid = process.pid

      print "Killing armagh running as PID #{pid}"
      Process.kill(:INT, pid)

      running = true
      while running
        begin
          Process.kill(0, pid)
          running = true
          print '.'
          sleep 0.25
        rescue Errno::ESRCH
          running = false
        end
      end
      puts ''
    end
  end
end
