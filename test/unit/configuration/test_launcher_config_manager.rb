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
require_relative '../test_helpers/mock_logger'

require_relative '../../../lib/configuration/launcher_config_manager'
require_relative '../../../lib/logging'

require 'log4r'
require 'test/unit'
require 'mocha/test_unit'

class TestLauncherConfigManager < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    Armagh::Logging.init_log_env

    @logger = mock
    @logger.stubs(:debug)
    @logger.stubs(:info)
    @logger.stubs(:warn)
    @logger.stubs(:error)
    @logger.stubs(:level=)

    @manager = LauncherConfigManager.new(@logger)
  end

  def launcher_config
    {'num_agents' => 5, 'checkin_frequency' => 120, 'log_level' => 'debug', 'timestamp' => Time.utc(100)}
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

    default_config = LauncherConfigManager::DEFAULT_CONFIG.merge ConfigManager::DEFAULT_CONFIG
    default_config['log_level'] = Log4r::DEBUG

    assert_equal(default_config, @manager.get_config)
  end

  def test_validate
    result = LauncherConfigManager.validate(launcher_config)
    assert_true result['valid']
    assert_empty result['warnings']
    assert_empty result['errors']
  end

  def test_negative_agents
    config = launcher_config
    config['num_agents'] = -1

    result = LauncherConfigManager.validate(config)
    assert_false result['valid']
    assert_include(result['errors'], "'num_agents' must be a Armagh::Configuration::ConfigManager::NonNegativeInteger object.  Was a Fixnum.")
    assert_empty result['warnings']
  end

  def test_zero_agents
    config = launcher_config
    config['num_agents'] = 0

    result = LauncherConfigManager.validate(config)
    assert_true result['valid']
    assert_empty result['errors']
    assert_empty result['warnings']
  end

  def test_bad_agents
    config = launcher_config
    config['num_agents'] = 'I am invalid'

    result = LauncherConfigManager.validate(config)
    assert_false result['valid']
    assert_include(result['errors'], "'num_agents' must be a Armagh::Configuration::ConfigManager::NonNegativeInteger object.  Was a String.")
    assert_empty result['warnings']
  end

  def test_validate_no_agents
    config = launcher_config
    config.delete('num_agents')

    result = LauncherConfigManager.validate(config)
    assert_true result['valid']
    assert_empty result['errors']
    assert_include(result['warnings'], "'num_agents' does not exist in the configuration.  Will use the default value of #{LauncherConfigManager.default_config['num_agents']}.")
  end

  def test_negative_checkin
    config = launcher_config
    config['checkin_frequency'] = -1

    result = LauncherConfigManager.validate(config)
    assert_false result['valid']
    assert_include(result['errors'], "'checkin_frequency' must be a Armagh::Configuration::ConfigManager::PositiveInteger object.  Was a Fixnum.")
    assert_empty result['warnings']
  end

  def test_bad_checkin
    config = launcher_config
    config['checkin_frequency'] = 'I am invalid'

    result = LauncherConfigManager.validate(config)
    assert_false result['valid']
    assert_include(result['errors'], "'checkin_frequency' must be a Armagh::Configuration::ConfigManager::PositiveInteger object.  Was a String.")
    assert_empty result['warnings']
  end

  def test_validate_no_checkin
    config = launcher_config
    config.delete('checkin_frequency')

    result = LauncherConfigManager.validate(config)
    assert_true result['valid']
    assert_empty result['errors']
    assert_include(result['warnings'], "'checkin_frequency' does not exist in the configuration.  Will use the default value of #{LauncherConfigManager.default_config['checkin_frequency']}.")
  end

  def test_validate_bad_timestamp
    config = launcher_config
    config['timestamp'] = 'bad'
    result = LauncherConfigManager.validate(config)
    assert_false result['valid']
    assert_empty result['warnings']
    assert_include(result['errors'], "'timestamp' must be a Time object.  Was a String.")
  end

  def test_validate_bad_log_level
    config = launcher_config
    config['log_level'] = 'bad'
    result = LauncherConfigManager.validate(config)
    assert_true result['valid']
    assert_include(result['warnings'], "'log_level' must be [\"fatal\", \"error\", \"warn\", \"info\", \"debug\"].  Was 'bad'.  Will use the default value of 'debug'.")
    assert_empty result['errors']
  end

  def test_validate_added_field
    config = launcher_config
    config['new_field'] = 'bad'
    result = LauncherConfigManager.validate(config)
    assert_true result['valid']
    assert_include(result['warnings'], 'The following settings were configured but are unknown: ["new_field"].')
    assert_empty result['errors']
  end
end