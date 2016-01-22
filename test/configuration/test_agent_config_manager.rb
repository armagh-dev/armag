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

require_relative '../test_helpers/coverage_helper'
require_relative '../test_helpers/mock_global_logger'
require_relative '../../lib/configuration/agent_config_manager'
require 'test/unit'
require 'mocha/test_unit'

class TestAgentConfigManager < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    @logger = mock
    @logger.stubs(:debug)
    @logger.stubs(:info)
    @logger.stubs(:warn)
    @logger.stubs(:error)
    @logger.stubs(:level=)

    @manager = AgentConfigManager.new(@logger)
  end

  def mock_config_find(result)
    find_result = mock('object')
    if result.is_a? Exception
      find_result.expects(:limit).with(1).raises(result)
    else
      find_result.expects(:limit).with(1).returns([result].flatten)
    end

    config = stub(:find => find_result)
    Armagh::Connection.stubs(:config).returns(config)
  end

  def test_merged_configs
    mock_config_find(nil)

    default_config = AgentConfigManager::DEFAULT_CONFIG.merge ConfigManager::DEFAULT_CONFIG
    default_config['log_level'] = Logger::DEBUG

    assert_equal(default_config, @manager.get_config)
  end
end