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

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../helpers/mock_logger'

require_relative '../../../lib/configuration/agent_config_manager'
require_relative '../../../lib/configuration/action_config_validator'
require_relative '../../../lib/logging'

require 'log4r'
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
    @logger.stubs(:ops_warn)
    @logger.stubs(:ops_error)
    @logger.stubs(:dev_warn)
    @logger.stubs(:dev_error)

    @manager = AgentConfigManager.new(@logger)
  end

  def agent_config
    {'available_actions' => {}, 'log_level' => 'debug', 'timestamp' => Time.utc(100)}
  end

  def mock_action_config_validator(result = nil)
    result ||= {'valid' => true, 'errors' => [], 'warnings' => []}
    Armagh::Configuration::ActionConfigValidator.any_instance.stubs(:validate).once.returns(result)
  end

  def mock_config_find(result)
    find_result = mock
    find_result.stubs(projection: find_result)
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
    default_config['log_level'] = Log4r::DEBUG

    assert_equal(default_config, @manager.get_config)
  end

  def test_validate
    mock_action_config_validator
    result = AgentConfigManager.validate(agent_config)
    assert_true result['valid']
    assert_empty result['warnings']
    assert_empty result['errors']
  end

  def test_validate_bad_timestamp
    config = agent_config
    config['timestamp'] = 'bad'
    Armagh::Configuration::ActionConfigValidator.any_instance.stubs(:validate).never
    result = AgentConfigManager.validate(config)
    assert_false result['valid']
    assert_empty result['warnings']
    assert_include(result['errors'], "'timestamp' must be a Time object.  Was a String.")
  end

  def test_validate_bad_log_level
    config = agent_config
    config['log_level'] = 'bad'
    mock_action_config_validator
    result = AgentConfigManager.validate(config)
    assert_true result['valid']
    assert_include(result['warnings'], "'log_level' must be [\"fatal\", \"error\", \"warn\", \"info\", \"debug\"].  Was 'bad'.  Will use the default value of 'debug'.")
    assert_empty result['errors']
  end

  def test_validate_added_field
    config = agent_config
    config['new_field'] = 'bad'
    mock_action_config_validator
    result = AgentConfigManager.validate(config)
    assert_true result['valid']
    assert_include(result['warnings'], 'The following settings were configured but are unknown: ["new_field"].')
    assert_empty result['errors']
  end
end