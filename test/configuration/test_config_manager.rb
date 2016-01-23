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
require_relative '../../lib/configuration/config_manager'
require 'test/unit'
require 'mocha/test_unit'

class TestConfigManager < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    @logger = mock
    @logger.stubs(:debug)
    @logger.stubs(:info)
    @logger.stubs(:warn)
    @logger.stubs(:error)
    @logger.stubs(:level=)
    @config_manager = ConfigManager.new('generic', @logger)

    @default_config = ConfigManager::DEFAULT_CONFIG.dup
    @default_config['log_level'] = Logger::DEBUG
  end

  def mock_config_find(result)
    find_result = mock('object')
    if result.is_a? Exception
      find_result.expects(:limit).with(1).raises(result).at_least_once
    else
      find_result.expects(:limit).with(1).returns([result].flatten).at_least_once
    end

    config = stub(:find => find_result)
    Armagh::Connection.stubs(:config).returns(config)
  end

  def test_get_config_none
    mock_config_find(nil)
    assert_equal(@default_config, @config_manager.get_config)
  end

  def test_get_config_error
    error_text = 'Error Text'
    mock_config_find(StandardError.new(error_text))
    assert_equal(@default_config, @config_manager.get_config)
  end

  def test_get_config_full
    config = {'available_actions' => {}, 'checkin_frequency' => 5, 'log_level' => 'info', 'num_agents' => 10, 'timestamp' => Time.new(0)}
    expected_config = config.dup
    expected_config['log_level'] = Logger::INFO
    mock_config_find(config)
    assert_equal(expected_config, @config_manager.get_config)
  end

  def test_get_config_partial
    config = {'checkin_frequency' => 123, 'unused_field' => 'howdy'}
    mock_config_find(config)
    assert_equal(@default_config.merge(config), @config_manager.get_config)
  end

  def test_get_updated_config
    config1 = {'available_actions' => {}, 'checkin_frequency' => 5, 'log_level' => 'info', 'num_agents' => 10, 'timestamp' => Time.new(0)}
    config2 = {'available_actions' => {}, 'checkin_frequency' => 2, 'log_level' => 'info', 'num_agents' => 5, 'timestamp' => Time.new(1)}
    expected_config = config2.dup
    expected_config['log_level'] = Logger::INFO

    mock_config_find(config1)
    @config_manager.get_config
    mock_config_find(config2)
    assert_equal(expected_config, @config_manager.get_config)
  end

  def test_get_older_config
    config1 = {'available_actions' => {}, 'checkin_frequency' => 5, 'log_level' => 'info', 'num_agents' => 10, 'timestamp' => Time.new(1)}
    config2 = {'available_actions' => {}, 'checkin_frequency' => 2, 'log_level' => 'info', 'num_agents' => 5, 'timestamp' => Time.new(0)}
    expected_config = config1.dup
    expected_config['log_level'] = Logger::INFO

    mock_config_find(config1)
    assert_equal(expected_config, @config_manager.get_config)
    mock_config_find(config2)
    assert_nil(@config_manager.get_config)
  end

  def test_get_config_multiple_times
    config = {'available_actions' => {}, 'checkin_frequency' => 5, 'log_level' => 'info', 'num_agents' => 10, 'timestamp' => Time.new(0)}
    expected_config = config.dup
    expected_config['log_level'] = Logger::INFO
    mock_config_find(config)
    assert_equal(expected_config, @config_manager.get_config)
    assert_nil(@config_manager.get_config)
  end

  def test_invalid_log_level
    config = {'log_level' => 'Invalid', 'checkin_frequency' => 111}
    expected_config = config.dup
    expected_config['log_level'] = Logger::DEBUG
    mock_config_find(config)

    actual_config = @config_manager.get_config

    assert_equal(@default_config['log_level'], actual_config['log_level'])
    assert_equal(expected_config['checkin_frequency'], actual_config['checkin_frequency'])
  end

  def test_get_log_level
    assert_equal(Logger::FATAL, @config_manager.get_log_level('FATAL'))
    assert_equal(Logger::ERROR, @config_manager.get_log_level('ERROR'))
    assert_equal(Logger::WARN, @config_manager.get_log_level('WaRn'))
    assert_equal(Logger::INFO, @config_manager.get_log_level('info'))
    assert_equal(Logger::DEBUG, @config_manager.get_log_level('debug'))
    assert_equal(Logger::DEBUG, @config_manager.get_log_level('Invalid'))
  end
end