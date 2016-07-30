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

require_relative '../../../lib/configuration/config_manager'
require_relative '../../../lib/logging'

require 'log4r'
require 'test/unit'
require 'mocha/test_unit'

class TestConfigManager < Test::Unit::TestCase
  include ArmaghTest
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

    @config_manager = ConfigManager.new('generic', @logger)

    @default_config = ConfigManager::DEFAULT_CONFIG.dup
    @default_config['log_level'] = Log4r::DEBUG
  end

  def mock_config_find(result)
    find_result = mock('object')
    find_result.stubs(projection: find_result)
    if result.is_a? Exception
      find_result.expects(:limit).with(1).raises(result).at_least_once
    else
      find_result.expects(:limit).with(1).returns([result].flatten).at_least_once
    end

    config = stub(:find => find_result)
    Armagh::Connection.stubs(:config).returns(config)
  end

  def config_for_validation
    {'log_level' => 'warn', 'timestamp' => Time.utc(2015, 11, 20)}
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
    expected_config['log_level'] = Log4r::INFO
    mock_config_find(config)
    assert_equal(expected_config, @config_manager.get_config)
  end

  def test_get_config_partial
    config = {'checkin_frequency' => 123, 'unused_field' => 'howdy'}
    mock_config_find(config)
    assert_equal(@default_config.merge(config), @config_manager.get_config)
  end

  def test_get_updated_config
    config1 = {'log_level' => 'info', 'timestamp' => Time.new(0)}
    config2 = {'log_level' => 'info', 'timestamp' => Time.new(1)}
    expected_config = config2.dup
    expected_config['log_level'] = Log4r::INFO

    mock_config_find(config1)
    @config_manager.get_config
    mock_config_find(config2)
    assert_equal(expected_config, @config_manager.get_config)
  end

  def test_get_older_config
    config1 = {'log_level' => 'info', 'timestamp' => Time.new(1)}
    config2 = {'log_level' => 'info','timestamp' => Time.new(0)}
    expected_config = config1.dup
    expected_config['log_level'] = Log4r::INFO

    mock_config_find(config1)
    assert_equal(expected_config, @config_manager.get_config)
    mock_config_find(config2)
    assert_nil(@config_manager.get_config)
  end

  def test_get_config_multiple_times
    config = {'log_level' => 'info', 'timestamp' => Time.new(0)}
    expected_config = config.dup
    expected_config['log_level'] = Log4r::INFO
    mock_config_find(config)
    assert_equal(expected_config, @config_manager.get_config)
    assert_nil(@config_manager.get_config)
  end

  def test_get_config_good_then_warn
    config1 = {'log_level' => 'info', 'timestamp' => Time.new(0)}
    config2 = {'log_level' => 'BKLAHABJDHF','timestamp' => Time.new(1)}
    expected_config1 = config1.dup
    expected_config1['log_level'] = Log4r::INFO

    mock_config_find(config1)
    assert_equal(expected_config1, @config_manager.get_config)

    expected_config2 = config2.dup
    mock_config_find(config2)
    expected_config2['log_level'] = Log4r::DEBUG
    assert_equal(expected_config2, @config_manager.get_config)
  end

  def test_get_config_error_first
    config = {'log_level' => 'info', 'timestamp' => 'BOO'}
    mock_config_find(config)
    assert_nil(@config_manager.get_config)
  end

  def test_get_config_error_update
    config1 = {'log_level' => 'info', 'timestamp' => Time.new(0)}
    config2 = {'log_level' => 'warn', 'timestamp' => 'BOO'}
    expected_config1 = config1.dup
    expected_config1['log_level'] = Log4r::INFO

    mock_config_find(config1)
    assert_equal(expected_config1, @config_manager.get_config)
    mock_config_find(config2)
    assert_nil(@config_manager.get_config)
  end

  def test_format_validation_no_messages
    validation_results = {'valid' => true, 'warnings' => [], 'errors' => []}
    result = ConfigManager.format_validation_results validation_results
    assert_equal('The configuration is valid.', result)
  end

  def test_format_validation_warnings
    validation_results = {'valid' => true, 'warnings' => ['Warning 1', 'Warning 2'], 'errors' => []}
    result = ConfigManager.format_validation_results validation_results
    assert_equal("The configuration is valid.\n\nWarnings: \n  Warning 1\n  Warning 2", result)
  end

  def test_format_validation_errors
    validation_results = {'valid' => false, 'warnings' => [], 'errors' => ['Error 1', 'Error 2']}
    result = ConfigManager.format_validation_results validation_results
    assert_equal("The configuration is invalid.\n\nErrors:\n  Error 1\n  Error 2", result)
  end

  def test_format_validation_warnings_and_errors
    validation_results = {'valid' => false, 'warnings' => ['Warning 1', 'Warning 2'], 'errors' => ['Error 1', 'Error 2']}
    result = ConfigManager.format_validation_results validation_results
    assert_equal("The configuration is invalid.\n\nWarnings: \n  Warning 1\n  Warning 2\n\nErrors:\n  Error 1\n  Error 2", result)
  end

  def test_validate
    result = ConfigManager.validate(config_for_validation)
    assert_true result['valid']
    assert_empty result['errors']
    assert_empty result['warnings']
  end

  def test_validate_empty_config
    result = ConfigManager.validate({})
    assert_true result['valid']
    assert_empty result['errors']
    assert_include(result['warnings'], "'timestamp' does not exist in the configuration.  Will use the default value of 0000-01-01 00:00:00 UTC.")
    assert_include(result['warnings'], "'log_level' does not exist in the configuration.  Will use the default value of debug.")
  end

  def test_validate_wrong_timestamp
    result = ConfigManager.validate({'timestamp' => 'Not a timestamp!'})
    assert_false result['valid']
    assert_include(result['errors'], "'timestamp' must be a Time object.  Was a String.")
  end

  def test_validate_extra_fields
    config = config_for_validation
    config['unknown'] = 'muhahaha'
    result = ConfigManager.validate config
    assert_true result['valid']
    assert_empty result['errors']
    assert_include(result['warnings'], 'The following settings were configured but are unknown: ["unknown"].')
  end

  def test_validate_missing_no_default
    ConfigManager::VALID_FIELDS['missing_field'] = String
    result = ConfigManager.validate(config_for_validation)
    ConfigManager::VALID_FIELDS.delete 'missing_field'
    assert_false result['valid']
    assert_include result['errors'], "'missing_field' does not exist in the configuration."
    assert_empty result['warnings']
  end

  def test_invalid_log_level
    config = {'log_level' => 'Invalid', 'checkin_frequency' => 111}
    expected_config = config.dup
    expected_config['log_level'] = Log4r::DEBUG
    mock_config_find(config)

    actual_config = @config_manager.get_config

    assert_equal(@default_config['log_level'], actual_config['log_level'])
    assert_equal(expected_config['checkin_frequency'], actual_config['checkin_frequency'])
  end

  def test_get_log_level
    assert_equal(Log4r::FATAL, @config_manager.get_log_level('FATAL'))
    assert_equal(Log4r::ERROR, @config_manager.get_log_level('ERROR'))
    assert_equal(Log4r::WARN, @config_manager.get_log_level('WaRn'))
    assert_equal(Log4r::INFO, @config_manager.get_log_level('info'))
    assert_equal(Log4r::DEBUG, @config_manager.get_log_level('debug'))
    assert_equal(Log4r::DEBUG, @config_manager.get_log_level('Invalid'))
  end
end
