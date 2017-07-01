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
require_relative '../../../lib/armagh/utils/collection_trigger'


require 'test/unit'
require 'mocha/test_unit'

class UTAction < Armagh::Actions::Collect
  def self.make_test_config(store:, action_name:, collected_doctype:)
    create_configuration(store, action_name, {
      'action' => {'name' => action_name, 'active' => true},
      'collect' => {'schedule' => '* * * * *', 'archive' => false},
      'input' => {},
      'output' => {
        'docspec' => Armagh::Documents::DocSpec.new(collected_doctype, Armagh::Documents::DocState::READY),
      }
    })
  end

  def self.make_long_test_config(store:, action_name:, collected_doctype:)
    create_configuration(store, action_name, {
      'action' => {'name' => action_name, 'active' => true},
      'collect' => {'schedule' => '* 0 1 * *', 'archive' => false},
      'input' => {},
      'output' => {
        'docspec' => Armagh::Documents::DocSpec.new(collected_doctype, Armagh::Documents::DocState::READY),
      }
    })
  end
end

class TestCollectionTrigger < Test::Unit::TestCase
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

    Armagh::Logging.expects(:set_logger).returns(@logger)
    @trigger = Armagh::Utils::CollectionTrigger.new(@workflow_set)
  end

  def test_start_stop_restart
    @trigger.instance_variable_get(:@last_run)['name'] = Time.now + 100
    assert_false @trigger.running?
    @trigger.start
    sleep RUN_SLEEP
    assert_true @trigger.running?
    @trigger.stop
    sleep RUN_SLEEP
    assert_false @trigger.running?
  end

  def test_start_log_errors
    @trigger.expects(:trigger_actions).raises(RuntimeError.new('Error'))
    Armagh::Logging.expects(:dev_error_exception)
    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop
  end

  def test_expired_run
    @trigger.instance_variable_get(:@last_run)['name'] = Time.at(0)
    Armagh::Document.expects(:create_trigger_document).with(:state => Armagh::Documents::DocState::READY, :type => '__COLLECT__name', :pending_actions => @actions)
    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop
  end

  def test_trigger_individual_collection
    Armagh::Document.expects(:create_trigger_document).with(:state => Armagh::Documents::DocState::READY, :type => '__COLLECT__name', :pending_actions => @actions)
    @trigger.trigger_individual_collection(@config)
  end

  def test_trigger_individual_collection_error
    Armagh::Document.expects(:create_trigger_document).raises(RuntimeError.new('nope'))
    Armagh::Logging.expects(:ops_error_exception)
    @trigger.trigger_individual_collection(@config)
  end

  def test_unseen
    @trigger.instance_variable_set(:@last_run, {'name' => Time.at(0).utc, 'old' => Time.at(0).utc})

    Armagh::Document.expects(:create_trigger_document).with(:state => Armagh::Documents::DocState::READY, :type => '__COLLECT__name', :pending_actions => @actions)
    @trigger.start
    sleep RUN_SLEEP
    @trigger.stop

    assert_equal(['name'], @trigger.instance_variable_get(:@last_run).keys)
  end

  def test_trigger_updated_workflow
    Armagh::Document.expects(:create_trigger_document).never

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