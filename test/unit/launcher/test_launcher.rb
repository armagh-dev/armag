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

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/launcher/launcher'
require_relative '../../../lib/armagh/logging'
require_relative '../../../lib/armagh/connection'

require 'mocha/test_unit'
require 'test/unit'
require 'configh'

class TestLauncher < Test::Unit::TestCase

  def setup
    @config_store = []
  end
  
  def assert_configure( candidate_values, exp_num_agents, exp_checkin_freq, exp_update_freq, exp_log_level, raises = nil, error_message = nil )
    
    if raises
      e = assert_raises( raises ) do
        Armagh::Launcher.create_configuration( @config_store, 'default', candidate_values )
      end
      assert_equal error_message, e.message
    else
      config = nil
      assert_nothing_raised do 
        config = Armagh::Launcher.create_configuration( @config_store, 'default', candidate_values )
      end
      assert_equal exp_num_agents, config.launcher.num_agents
      assert_equal exp_checkin_freq, config.launcher.checkin_frequency
      assert_equal exp_update_freq, config.launcher.update_frequency
      assert_equal exp_log_level, config.launcher.log_level
    end
  end
  
  def test_configure_with_defaults
    assert_configure( {}, 1, 60, 60, 'info' )
  end
  
  def test_configure_set_num_agents_valid
    assert_configure( { 'launcher' => { 'num_agents' => 2 }}, 2, 60, 60, 'info' )
  end
  
  def test_configure_set_num_agents_invalid
    assert_configure( { 'launcher' => { 'num_agents' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, 'Unable to create configuration Armagh::Launcher default: launcher num_agents: type validation failed: value 0 is non-positive' )
  end
  
  def test_configure_set_checkin_frequency_valid
    assert_configure( { 'launcher' => { 'checkin_frequency' => 300 }}, 1, 300, 60, 'info' )
  end
  
  def test_configure_set_checkin_frequency_invalid
    assert_configure( { 'launcher' => { 'checkin_frequency' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, 'Unable to create configuration Armagh::Launcher default: launcher checkin_frequency: type validation failed: value 0 is non-positive' )
  end
  
  def test_configure_set_update_frequency_valid
    assert_configure( { 'launcher' => { 'update_frequency' => 300 }}, 1, 60, 300, 'info' )
  end
  
  def test_configure_set_update_frequency_invalid
    assert_configure( { 'launcher' => { 'update_frequency' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, 'Unable to create configuration Armagh::Launcher default: launcher update_frequency: type validation failed: value 0 is non-positive' )
  end
    
  def test_configure_set_log_level_valid
    assert_configure( { 'launcher' => { 'log_level' => 'debug' }}, 1, 60, 60, 'debug' )
  end

  def test_configure_set_log_level_invalid
    assert_configure( { 'launcher' => { 'log_level' => 'fred' }}, nil, nil, nil, nil, Configh::ConfigInitError, 'Unable to create configuration Armagh::Launcher default: Log level must be one of all, debug, info, warn, dev_warn, ops_warn, error, dev_error, ops_error, fatal, any, off' )
  end
      
end
 