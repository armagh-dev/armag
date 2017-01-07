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
    DAEMON_DIR = '/tmp/armagh'
  end
  
  def self.start_launcher_daemon
    raise "Unable to write to #{DAEMON_DIR}" unless File.writable? DAEMON_DIR
    system "#{DAEMON} start > /dev/null"
    sleep 1
  end
  
  def self.stop_launcher_daemon
    system "#{DAEMON} stop > /dev/null"
    sleep 4
  end
  
  def self.launch_launcher
    rout, wout = IO.pipe
    rerr, werr = IO.pipe

    pid = Process.spawn("#{EXEC}", :out => wout, :err => werr)
    Process.detach(pid)
    sleep 1

    {pid: pid, stdout: {read: rout, write: wout}, stderr: {read: rerr, write: werr}}
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

      puts "Killing armagh running as PID #{pid}"
      Process.kill(:SIGINT, pid)
      begin
        Process.waitpid(pid)
      rescue Errno::ECHILD; end
    end
    sleep 1
  end
end
