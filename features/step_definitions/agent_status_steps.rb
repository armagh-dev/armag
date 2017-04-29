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

require_relative '../../test/helpers/mongo_support'
require_relative '../../lib/version'

require 'test/unit/assertions'

Then(/^I should see an agent with a status of "([^"]*)" within (\d+) seconds*$/) do |status, seconds|
  end_time = Time.now + seconds.to_i
  found_status = false

  until (Time.now > end_time) || found_status
    db_status = MongoSupport.instance.get_status
    if db_status
      agent_status = db_status['agents']
      found_status = agent_status.collect{|_a,s| s['status']}.include? status
    end
    sleep 0.25
  end

  assert_true(found_status, "No agents were seen with a status of #{status}")
end

Then(/^I wait until there are agents with the statuses$/) do |table|
  end_time = Time.now + 15 # time limit (seconds)
  matched_statuses = false

  expected_agent_statuses = table.raw.flatten.sort
  expected_agent_statuses = expected_agent_statuses.delete_if {|e| e == 'nil'}.sort

  until (Time.now > end_time) || matched_statuses
    status = MongoSupport.instance.get_status
    if status
      agents = status['agents']
      seen_statuses = []
      agents.each do |_id, details|
        seen_statuses << details['status']
      end
      seen_statuses.sort!
      matched_statuses = seen_statuses == expected_agent_statuses
    end
    sleep 0.1
  end

  assert_equal(expected_agent_statuses, seen_statuses, 'Agents were not seen with the expected statuses')
end


Then(/^the valid reported status should contain agents with statuses$/) do |table|
  start_time = Time.now.utc

  expected_agent_statuses = table.raw.flatten.sort
  expected_agent_statuses = expected_agent_statuses.delete_if {|e| e == 'nil'}
  status = MongoSupport.instance.get_status

  agents = status['agents']
  assert_equal(expected_agent_statuses.length, agents.length, 'Incorrect number of agents')

  seen_statuses = []
  agents.each do |id, details|
    assert_not_empty(id)
    assert_in_delta(start_time, details['last_update'], 10, 'Incorrect agent last_update time')

    agent_status = details['status']

    if agent_status == 'idle'
      assert_in_delta(start_time, details['idle_since'], 10, 'Incorrect agent idle_since')
    elsif agent_status == 'running'
      assert_in_delta(start_time, details['running_since'], 10, 'Incorrect agent idle_since')
      assert_not_empty(details['task'])
    else
      flunk "Status #{agent_status} should be 'running' or 'idle'"
    end

    seen_statuses << agent_status
  end
  seen_statuses.sort!

  assert_equal(expected_agent_statuses, seen_statuses, 'Incorrect agent statuses')
  assert_in_delta(start_time, status['last_update'], 5, 'Incorrect last_update')

  assert_equal(Armagh::VERSION, status['versions']['armagh'], 'Invalid version')
end

