# Copyright 2016 Noragh Analytics, Inc.
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

require_relative '../support/launcher_support'
require_relative '../../test/helpers/mongo_support'

require 'test/unit/assertions'
require 'time'

Given(/^armagh isn't already running$/) do
  LauncherSupport.kill_launcher_processes
  assert_true LauncherSupport.get_launcher_processes.empty?
end

When(/^armagh doesn't have a "([^"]*)" config$/) do |config_type|
  MongoSupport.instance.delete_config(config_type)
end

When(/^I run armagh$/) do
  launch_details = LauncherSupport.launch_launcher
  @spawn_pid = launch_details[:pid]
  @stderr_pipe = launch_details[:stderr]
  @stdout_pipe = launch_details[:stdout]
  sleep 3
end

Then(/^armagh should have exited$/) do
  assert_false LauncherSupport.running?(@spawn_pid)
end

Then(/^armagh should be running$/) do
  assert_true LauncherSupport.running?(@spawn_pid)
end

Then(/^stderr should contain "([^"]*)"$/) do |message|
  @stderr_pipe[:write].close
  stderr = @stderr_pipe[:read].readlines.join("\n").strip
  assert_not_nil stderr =~ /#{message}/, "Stderr does not contain '#{message}'."
end

Then(/^the number of running agents equals (\d+)$/) do |num_agents|
  assert_equal(num_agents.to_i, LauncherSupport.get_agent_processes.size)
end

When(/^an agent is killed/) do
  @original_agents = LauncherSupport.get_agent_processes
  @agent_to_kill = @original_agents.last.pid
  Process.kill(:SIGKILL, @agent_to_kill)
  sleep 3
end

Then(/^a new agent shall launch to take its place$/) do
  agents = LauncherSupport.get_agent_processes
  assert_equal(@original_agents.size, agents.size)
  assert_false agents.include?(@agent_to_kill)
end

When(/^I run armagh as a daemon$/) do
  LauncherSupport.start_launcher_daemon
end

Then(/^armagh should run in the background$/) do
  status = LauncherSupport.get_daemon_status
  assert_match(/armagh-agentsd is running as PID \d+/, status)
  @spawn_pid = status[/\d+/].to_i
end

Then(/^the armagh daemon can be stopped$/) do
  LauncherSupport.stop_launcher_daemon
  assert_true LauncherSupport.get_launcher_processes.empty?
end

When(/^the armagh daemon is killed$/) do
  status = LauncherSupport.get_daemon_status
  assert_match(/running \[pid \d+\]/, status)
  @old_pid = status[/\d+/].to_i

  Process.kill(:SIGTERM, @old_pid)
end

