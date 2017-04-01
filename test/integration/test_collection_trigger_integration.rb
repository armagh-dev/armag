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

require_relative '../helpers/coverage_helper'

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'
require_relative '../helpers/mock_logger'

require_relative '../../lib/utils/collection_trigger'
require_relative '../../lib/ipc'
require_relative '../../lib/agent/agent_status'

require 'armagh/actions'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

module Armagh
  module StandardActions
    class CollectActionForTest < Actions::Collect
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

    class SplitActionForTest < Actions::Split
      def self.make_test_config( store:, action_name:, input_doctype:, output_doctype: )
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, Armagh::Documents::DocState::READY ) },
          'output' => { 'docspec'  => Armagh::Documents::DocSpec.new( output_doctype, Armagh::Documents::DocState::READY )}
        })
      end
    end
  end
end

class TestCollectTriggerIntegration < Test::Unit::TestCase
  include ArmaghTest

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

  def setup
    @logger = mock_logger
    MongoSupport.instance.clean_database
    @config_store = []

    @collect_config = Armagh::StandardActions::CollectActionForTest.make_test_config(store: @config_store, action_name: 'collect_action', collected_doctype: 'collect_type')
    Armagh::StandardActions::SplitActionForTest.make_test_config(store: @config_store, action_name: 'split_action', input_doctype: 'incoming_split', output_doctype: 'outgoing_split')

    @workflow = Armagh::Actions::Workflow.new(@logger, @config_store)
    @collection_trigger = Armagh::Utils::CollectionTrigger.new(@workflow)
  end

  def teardown
    @collection_trigger.stop if @collection_trigger.running?
  end

  def wait_for_documents(seconds)
    end_time = Time.now + seconds
    while MongoSupport.instance.get_mongo_documents('documents').to_a.empty?
      fail ('Document was never inserted') if Time.now > end_time
      sleep 1
    end
  end

  def test_triggered_collect
    assert_empty MongoSupport.instance.get_mongo_documents('documents').to_a
    @collection_trigger.trigger_individual_collection @collect_config

    assert_equal 1, MongoSupport.instance.get_mongo_documents('documents').to_a.length
    doc1 =  MongoSupport.instance.get_mongo_documents('documents').first

    assert_false doc1['locked']
    assert_equal(['collect_action'], doc1['pending_actions'])
    assert_include(doc1['type'], 'collect_action')

    @collection_trigger.trigger_individual_collection @collect_config
    assert_equal 1, MongoSupport.instance.get_mongo_documents('documents').to_a.length
    doc2 =  MongoSupport.instance.get_mongo_documents('documents').first
    assert_equal(doc1, doc2)
  end

  def test_timed_collection
    assert_empty MongoSupport.instance.get_mongo_documents('documents').to_a
    sec = Time.now.sec
    sleep 61 - sec if sec >= 55
    sleep 1 if sec < 1

    @collection_trigger.start
    wait_for_documents(70)

    MongoSupport.instance.clean_database
    assert_empty MongoSupport.instance.get_mongo_documents('documents').to_a
    wait_for_documents(60)
    @collection_trigger.stop
  end

  def test_collection_config_change
    MongoSupport.instance.clean_database
    @config_store.clear

    Armagh::StandardActions::CollectActionForTest.make_long_test_config(store: @config_store, action_name: 'change_collect', collected_doctype: 'collect_type')
    @workflow.refresh

    @collection_trigger.start

    sleep 62
    Armagh::StandardActions::CollectActionForTest.make_test_config(store: @config_store, action_name: 'change_collect2', collected_doctype: 'collect_type')
    @workflow.refresh
    sleep 1

    assert_empty MongoSupport.instance.get_mongo_documents('documents').to_a
  end
end
