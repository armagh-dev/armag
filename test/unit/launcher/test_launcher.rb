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
require_relative '../../helpers/armagh_test/logger'

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/launcher/launcher'
require_relative '../../../lib/armagh/logging'
require_relative '../../../lib/armagh/connection'
require_relative '../../../lib/armagh/status'

require 'socket'
require 'mocha/test_unit'
require 'test/unit'
require 'configh'

class TestLauncher < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @config_store = []
    mock_collection_trigger
    mock_connection
    mock_authentication

    Armagh::Logging.stubs(:set_level)

    @launcher_config = mock('launcher_config')
    @agent_config = mock('agent_config')
    @archiver_config = mock('archiver_config')
    @authentication_config = mock('@authentication_config')
    lc = mock
    lc.stubs(:log_level).returns(Armagh::Logging::FATAL)
    @launcher_config.stubs(:launcher).returns(lc)
    Armagh::Launcher.stubs(:find_or_create_configuration).returns(@launcher_config)
    Armagh::Agent.stubs(:find_or_create_configuration).returns(@agent_config)
    Armagh::Utils::Archiver.stubs(:find_or_create_configuration).returns(@archiver_config)
    Armagh::Authentication::Configuration.stubs(:find_or_create_configuration).returns(@authentication_config)

    @workflow_set = mock('workflow_set')
    Armagh::Actions::WorkflowSet.stubs(:for_agent).returns(@workflow_set)

    Armagh::Logging.stubs(:set_logger).returns(mock_logger)
    @launcher = Armagh::Launcher.new
  end

  def mock_collection_trigger
    @collection_trigger = mock
    @collection_trigger.stubs(:start)
    @collection_trigger.stubs(:stop)
    @collection_trigger.stubs(:logger)
    Armagh::Utils::ScheduledActionTrigger.stubs(:new).returns(@collection_trigger)
  end

  def mock_connection
    Armagh::Connection.stubs(:require_connection)
    Armagh::Connection.stubs(:config).returns(@config)
    Armagh::Connection.stubs(:ip).returns('10.10.10.10')
  end

  def mock_authentication
    Armagh::Authentication::User.stubs :setup_default_users
    Armagh::Authentication::Group.stubs :setup_default_groups
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
    assert_configure( { 'launcher' => { 'num_agents' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, "Unable to create configuration for 'Armagh::Launcher' named 'default' because: \n    Group 'launcher' Parameter 'num_agents': type validation failed: value '0' is non-positive" )
  end

  def test_configure_set_checkin_frequency_valid
    assert_configure( { 'launcher' => { 'checkin_frequency' => 300 }}, 1, 300, 60, 'info' )
  end

  def test_configure_set_checkin_frequency_invalid
    assert_configure( { 'launcher' => { 'checkin_frequency' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, "Unable to create configuration for 'Armagh::Launcher' named 'default' because: \n    Group 'launcher' Parameter 'checkin_frequency': type validation failed: value '0' is non-positive" )
  end

  def test_configure_set_update_frequency_valid
    assert_configure( { 'launcher' => { 'update_frequency' => 300 }}, 1, 60, 300, 'info' )
  end

  def test_configure_set_update_frequency_invalid
    assert_configure( { 'launcher' => { 'update_frequency' => 0 }}, nil, nil, nil, nil, Configh::ConfigInitError, "Unable to create configuration for 'Armagh::Launcher' named 'default' because: \n    Group 'launcher' Parameter 'update_frequency': type validation failed: value '0' is non-positive" )
  end

  def test_configure_set_log_level_valid
    assert_configure( { 'launcher' => { 'log_level' => 'debug' }}, 1, 60, 60, 'debug' )
  end

  def test_configure_set_log_level_invalid
    assert_configure( { 'launcher' => { 'log_level' => 'fred' }}, nil, nil, nil, nil, Configh::ConfigInitError, "Unable to create configuration for 'Armagh::Launcher' named 'default' because: \n    Group 'launcher' Parameter 'log_level': value is not one of the options (debug,info,warn,ops_warn,dev_warn,error,ops_error,dev_error,fatal,any)" )
  end

  def test_checkin_running
    Armagh::Status::LauncherStatus.expects(:report).with do |args|
      assert_equal Socket.gethostname, args[:hostname]
      assert_equal Armagh::Status::RUNNING, args[:status]
      assert args[:versions].key? 'armagh'
      assert args[:versions].key? 'actions'
      true
    end

    @launcher.checkin(Armagh::Status::RUNNING)
  end

  def test_checkin_not_running
    Armagh::Status::LauncherStatus.expects(:report).with do |args|
      assert_equal Socket.gethostname, args[:hostname]
      assert_equal Armagh::Status::STOPPING, args[:status]
      assert args[:versions].key? 'armagh'
      assert args[:versions].key? 'actions'
      assert_nil args[:started]
      true
    end

    @launcher.checkin(Armagh::Status::STOPPING)
  end
      
end
 
