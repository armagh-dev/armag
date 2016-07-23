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
require_relative '../../../lib/environment.rb'
Armagh::Environment.init

require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/agent/agent_status'
require 'test/unit'

class TestAgentStatus < Test::Unit::TestCase

  def setup
    @agent_status = Armagh::AgentStatus.new
  end

  def teardown
  end

  def report_statuses
    agents = %w(one two three)

    agents.each do |agent|
      @agent_status.report_status(agent, {'empty_status' => agent})
    end
    agents
  end

  def test_report_status
    assert_true(Armagh::AgentStatus.get_statuses(@agent_status).empty?)

    agents = report_statuses

    assert_equal(agents.length, Armagh::AgentStatus.get_statuses(@agent_status).length)

    agents.each do |agent|
      assert_equal({'empty_status' => agent}, Armagh::AgentStatus.get_statuses(@agent_status)[agent])
    end
  end

  def test_remove_agent
    assert_true(Armagh::AgentStatus.get_statuses(@agent_status).empty?)

    agents = report_statuses

    assert_equal(agents.length, Armagh::AgentStatus.get_statuses(@agent_status).length)

    last_agent = agents.last

    @agent_status.remove_agent(last_agent)

    assert_equal(agents.length - 1, Armagh::AgentStatus.get_statuses(@agent_status).length)
    assert_false Armagh::AgentStatus.get_statuses(@agent_status).has_key?(last_agent)
  end

  def test_set_config
    config = {'test' => 'config'}
    @agent_status.config = config
    assert_equal(config, Armagh::AgentStatus.get_config(@agent_status))
  end

  def test_update_config
    config = {'test' => 'config'}
    @agent_status.config = config
    @agent_status.update_config('new', 'value')
    assert_equal({'new' => 'value', 'test' => 'config'}, Armagh::AgentStatus.get_config(@agent_status))
  end
end