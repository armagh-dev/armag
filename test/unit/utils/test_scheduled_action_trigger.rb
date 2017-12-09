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
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/logging'
require_relative '../../../lib/armagh/utils/scheduled_action_trigger'


require 'facets/kernel/attr_singleton'

require 'test/unit'
require 'mocha/test_unit'

class UTAction < Armagh::Actions::Collect
  def self.make_test_config(store:, action_name:, collected_doctype:)
    create_configuration(store, action_name, {
      'action' => {'name' => action_name, 'active' => true, 'workflow' => 'wf'},
      'collect' => {'schedule' => '* * * * *', 'archive' => false},
      'input' => {},
      'output' => {
        'docspec' => Armagh::Documents::DocSpec.new(collected_doctype, Armagh::Documents::DocState::READY),
      }
    })
  end

  def self.make_long_test_config(store:, action_name:, collected_doctype:)
    create_configuration(store, action_name, {
      'action' => {'name' => action_name, 'active' => true, 'workflow' => 'wf'},
      'collect' => {'schedule' => '* 0 1 * *', 'archive' => false},
      'input' => {},
      'output' => {
        'docspec' => Armagh::Documents::DocSpec.new(collected_doctype, Armagh::Documents::DocState::READY),
      }
    })
  end
end

class TestScheduledActionTrigger < Test::Unit::TestCase
  include ArmaghTest

  RUN_SLEEP = 0.5

  def setup
    @config_store = []

    @logger = mock_logger
    @logger.unstub(:dev_error)
    @logger.unstub(:ops_error)
    @workflow_set = mock('workflow_set')
    @workflow_set.stubs(:config_store).returns(@config_store)
    @actions = ['one']
    @workflow_set.stubs(:actions_names_handling_docspec).returns(@actions)
    @last_timestamp = Time.new(2010, 3, 5, 23, 32, 0)
    @workflow_set.stubs(:last_timestamp).returns(@last_timestamp)
    @config = UTAction.make_test_config(store: @config_store, action_name: 'name', collected_doctype: 'type')
    @workflow_set.stubs(:collect_action_configs).returns([@config])
    @workflow_set.stubs(:utility_action_configs).returns([])
  end

  def setup_good_trigger_new_config
    Armagh::Logging.expects(:set_logger).returns(@logger)
    @hostname = 'thehost'
    @mock_doc = Object.new
    @mock_doc.attr_singleton_accessor :last_run, :seen_actions, :locked_by_me_until
    @mock_doc.last_run = {}
    @mock_doc.seen_actions = []
    def @mock_doc.locked_by_me_until(me);  Time.now.utc + 60; end
    def @mock_doc.locked_by_anyone?; true; end
    @mock_doc.expects(:save).at_least_once
    Armagh::TriggerManagerSemaphoreDocument.expects( :create_one_unlocked ).returns( 'inserted_id_response' )
  end

  def setup_good_trigger_existing_config
    Armagh::Logging.expects(:set_logger).returns(@logger)
    @hostname = 'thehost'
    @mock_doc = Object.new
    @mock_doc.attr_singleton_accessor :last_run, :seen_actions
    @mock_doc.last_run = {}
    @mock_doc.seen_actions = []
    Armagh::TriggerManagerSemaphoreDocument.expects(:create_one_unlocked).raises(Armagh::Connection::DocumentUniquenessError)
  end

  def setup_run
    @trigger = Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    Armagh::TriggerManagerSemaphoreDocument.expects(:find_one_locked).at_least_once.with( { 'name' => 'trigger_manager_document' }, @trigger).returns( @mock_doc )
  end

  def setup_dont_run
    @trigger = Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    Armagh::TriggerManagerSemaphoreDocument.expects(:find_one_locked).at_least_once.with( { 'name' => 'trigger_manager_document' }, @trigger).returns( nil )
   end

  def setup_trigger_db_error
    Armagh::Logging.expects(:set_logger).returns(@logger)
    @hostname = 'thehost'
    @mock_doc = Object.new
    @mock_doc.attr_singleton_accessor :last_run, :seen_actions
    @mock_doc.last_run = {}
    @mock_doc.seen_actions = []
    Armagh::TriggerManagerSemaphoreDocument.expects( :create_one_unlocked).raises( StandardError)
  end

  def test_initialize_config_exists
    assert_nothing_raised do
      setup_good_trigger_existing_config
      Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    end
  end

  def test_initialize_db_error
    assert_raises( StandardError ) do
      setup_trigger_db_error
      Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    end
  end

  def test_start_stop_restart
    setup_good_trigger_new_config
    setup_run

    time_plus_100 = Time.now + 100
    @trigger.instance_variable_get(:@last_run)['name'] = time_plus_100
    assert_false @trigger.running?

    @trigger.start
    sleep RUN_SLEEP
    assert_true @trigger.running?
    @trigger.stop
    sleep RUN_SLEEP
    assert_false @trigger.running?
  end

  def test_start_log_errors
    setup_good_trigger_existing_config
    setup_run
    @trigger.expects(:trigger_actions).at_least_once.raises(RuntimeError.new('Error'))
    Armagh::Logging.expects(:dev_error_exception).at_least_once
    @mock_doc.expects(:save)
    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop
  end

  def test_expired_run
    setup_good_trigger_new_config
    setup_run
    @mock_doc.last_run['name'] = Time.at(0)
    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop
  end

  def test_no_triggering_if_not_responsible_for_triggering_actions
    setup_good_trigger_existing_config
    setup_dont_run
    @trigger.start
    sleep 5
    @trigger.stop
  end

  def test_trigger_individual_action
    setup_good_trigger_existing_config
    @trigger = Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    Armagh::ActionTriggerDocument.expects(:ensure_one_exists).with(:state => Armagh::Documents::DocState::READY, :type => '__COLLECT__name', :pending_actions => @actions, :logger => @logger)
    @trigger.trigger_individual_action(@config)
  end

  def test_trigger_individual_action_error
    setup_good_trigger_existing_config
    @trigger = Armagh::Utils::ScheduledActionTrigger.new(@workflow_set)
    Armagh::ActionTriggerDocument.expects(:ensure_one_exists).raises(RuntimeError.new('nope'))
    Armagh::Logging.expects(:ops_error_exception)
    @trigger.trigger_individual_action(@config)
  end

  def test_unseen
    setup_good_trigger_new_config
    setup_run
    @mock_doc.last_run = {'name' => Time.at(0).utc, 'old' => Time.at(0).utc}

    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop

    assert_equal(['name'], @trigger.instance_variable_get(:@last_run).keys)
  end

  def test_trigger_updated_workflow
    setup_good_trigger_new_config
    setup_run
    Armagh::ActionTriggerDocument.expects(:ensure_one_exists).never

    @config = UTAction.make_long_test_config(store: @config_store, action_name: 'update1', collected_doctype: 'type')
    @workflow_set.stubs(:collect_action_configs).returns([@config])
    @workflow_set.stubs(:last_timestamp).returns(Time.new(2010, 1, 5, 20, 35))
    @trigger.start
    sleep RUN_SLEEP

    @config = UTAction.make_test_config(store: @config_store, action_name: 'update2', collected_doctype: 'type')
    @workflow_set.stubs(:last_timestamp).returns(Time.new(2010, 1, 5, 23, 35))
    @workflow_set.stubs(:last_timestamp).returns(Time.now)
    sleep RUN_SLEEP
    @trigger.stop
  end
end
