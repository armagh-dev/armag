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
require_relative '../../lib/configuration/launcher_config'
require 'test/unit'
require 'mocha/test_unit'

class TestLauncherConfig < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    ArmaghTest.mock_global_logger
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

  def test_singleton
    assert_same(LauncherConfig.instance, Armagh::Configuration::LauncherConfig.instance)
  end

  def test_singleton_no_new
    assert_raise NoMethodError do
      LauncherConfig.new
    end
  end

  def test_get_config_none
    mock_config_find(nil)
    assert_equal(LauncherConfig::DEFAULT_CONFIG, LauncherConfig.get_config)
  end

  def test_get_config_error
    error_text = 'Error Text'
    mock_config_find(StandardError.new(error_text))
    assert_equal(LauncherConfig::DEFAULT_CONFIG, LauncherConfig.get_config)
  end

  def test_get_config_full
    config = {'available_actions' => {}, 'checkin_frequency' => 5, 'log_level' => Logger::INFO, 'num_agents' => 10, 'timestamp' => Time.new(0)}
    expected_config = config.dup
    mock_config_find(config)
    assert_equal(expected_config, LauncherConfig.get_config)
  end

  def test_get_config_partial
    config = {'checkin_frequency' => 123, 'unused_field' => 'howdy'}
    mock_config_find(config)
    assert_equal(LauncherConfig::DEFAULT_CONFIG.merge(config), LauncherConfig.get_config)
  end

  def test_invalid_log_level
    config = {'log_level' => 'Invalid', 'checkin_frequency' => 111}
    expected_config = config.dup
    expected_config['log_level'] = LauncherConfig::DEFAULT_CONFIG['log_level']
    mock_config_find(config)

    actual_config = LauncherConfig.get_config

    assert_equal(LauncherConfig::DEFAULT_CONFIG['log_level'], actual_config['log_level'])
    assert_equal(expected_config['checkin_frequency'], actual_config['checkin_frequency'])
  end
end