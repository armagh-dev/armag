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

require_relative '../../../helpers/coverage_helper'
require_relative '../../../helpers/workflow_generator_helper'
require_relative '../../../helpers/armagh_test'
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../../lib/armagh/actions/utility_actions/db_cleanup_utility_action'
require_relative '../../../../lib/armagh/document/document'
require_relative '../../../../lib/armagh/document/action_state_document'
require_relative '../../../../lib/armagh/document/trigger_manager_semaphore_document'
require_relative '../../../../lib/armagh/logging/alert'

require 'armagh/actions'
require_relative '../../../../lib/armagh/actions/workflow_set'

class TestDBCleanupUtilityAction < Test::Unit::TestCase
  include ArmaghTest

  def good_alice_in_db
    @wf_set ||= Armagh::Actions::WorkflowSet.for_admin( Armagh::Connection.config, logger: @logger )
    @alice = @wf_set.create_workflow({ 'workflow' => { 'name' => 'alice'}} )
    @alice_workflow_actions_config_values.each do |type,action_config_values|
      @alice.create_action_config(type, action_config_values)
    end
    @alice
  end

  def good_fred_in_db
    @wf_set ||= Armagh::Actions::WorkflowSet.for_admin( Armagh::Connection.config, logger: @logger )
    @fred = @wf_set.create_workflow({ 'workflow' => { 'name' => 'fred'}} )
    @fred_workflow_actions_config_values.each do |type,action_config_values|
      @fred.create_action_config(type, action_config_values)
    end
    @fred
  end

  def expect_calls_find_alice_docs_in_db
    Armagh::Document
        .expects(:count_failed_and_in_process_documents_by_doctype )
        .at_least_once
        .returns( [
            { 'category' => 'in process', 'docspec_string' => 'a_alicedoc:ready',       'count' =>9},
            { 'category' => 'in process', 'docspec_string' => 'b_alicedocs_aggr:ready', 'count' =>20},
            { 'category' => 'failed',     'docspec_string' => 'a_alicedoc:ready',       'count'=>3 },
            { 'category' => 'in process', 'docspec_string' => 'a_alicedoc:published',   'published_collection' => 'a_alicedoc', 'count' => 12 }
        ])
     Armagh::Logging::Alert.stubs( get_counts: { 'warn' => 0, 'error' => 0, 'fatal' => 0})
  end

  def expect_calls_find_no_alice_docs_in_db
    Armagh::Document
        .expects(:count_failed_and_in_process_documents_by_doctype)
        .at_least_once
        .returns([])
    Armagh::Logging::Alert.stubs( get_counts: { 'warn' => 0, 'error' => 0, 'fatal' => 0})
  end

  def expect_alice_run_finds_documents
    expect_calls_find_alice_docs_in_db
  end

  def expect_alice_stopping_finds_documents
    expect_calls_find_alice_docs_in_db
  end
  def expect_alice_stop_finds_documents
    expect_calls_find_alice_docs_in_db
  end

  def expect_alice_stop_finds_no_documents
    expect_calls_find_no_alice_docs_in_db
  end

  def setup
    @caller = mock
    @logger = mock_logger
    Armagh::Actions::UtilityAction.any_instance.stubs( logger: @logger )
    @config_store = []
    Armagh::Connection.stubs( :config ).returns( @config_store )
    @workflow_set = Armagh::Actions::WorkflowSet.for_agent( @config_store, logger: @logger )
    @alice_workflow_config_values = {'workflow'=>{'name'=>'alice'}}
    @alice_workflow_actions_config_values = WorkflowGeneratorHelper.workflow_actions_config_values_with_no_unused_output( 'alice' )
    @fred_workflow_config_values = {'workflow'=>{'name' => 'fred'}}
    @fred_workflow_actions_config_values  = WorkflowGeneratorHelper.workflow_actions_config_values_no_divide('fred')

    cleanup_config = Armagh::Actions::UtilityActions::DBCleanUpUtilityAction.create_configuration(
        @config_store,
        'dbcleanuputilityaction',
        Armagh::Actions::UtilityActions::DBCleanUpUtilityAction.default_config_values,
        maintain_history: false
    )
    @db_cleanup_utility_action = Armagh::Actions::UtilityActions::DBCleanUpUtilityAction.new(
        @caller,
        @logger,
        cleanup_config )
  end

  def teardown
  end

  def test_try_run
    @db_cleanup_utility_action.expects( :try_to_move_stopping_workflows_to_stopped )
    @db_cleanup_utility_action.expects( :reset_expired_locks )
    @db_cleanup_utility_action.run
  end

  def test_try_to_move_stopping_workflows_to_stopped_nothing_to_do
    good_alice_in_db
    good_fred_in_db

    wf_set = nil
    assert_nothing_raised do
      wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store, logger: @logger )
    end

    alice = wf_set.get_workflow('alice')
    fred = wf_set.get_workflow('fred')

    expect_alice_run_finds_documents
    alice.run

    @db_cleanup_utility_action.try_to_move_stopping_workflows_to_stopped

    assert alice.running?
  end

  def test_try_to_move_stopping_workflows_to_stopped_no_docs_left
    good_alice_in_db
    good_fred_in_db

    wf_set = nil
    assert_nothing_raised do
      wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store, logger: @logger )
    end

    alice = wf_set.get_workflow('alice')
    fred = wf_set.get_workflow('fred')

    expect_alice_run_finds_documents
    alice.run
    assert alice.running?

    expect_alice_stop_finds_documents
    assert_raises Armagh::Actions::WorkflowDocumentsInProcessError.new("Cannot stop - 41 documents still processing") do
      alice.stop
    end
    assert alice.stopping?

    expect_alice_stop_finds_no_documents
    stat = @db_cleanup_utility_action.try_to_move_stopping_workflows_to_stopped

    assert Armagh::Actions::WorkflowSet.for_agent(@config_store).get_workflow( 'alice' ).stopped?
  end

  def test_try_to_move_stopping_workflows_to_stopped_docs_left
    good_alice_in_db
    good_fred_in_db

    wf_set = nil
    assert_nothing_raised do
      wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store, logger: @logger )
    end

    alice = wf_set.get_workflow('alice')

    expect_alice_run_finds_documents
    alice.run
    assert alice.running?

    expect_alice_stop_finds_documents
    assert_raises Armagh::Actions::WorkflowDocumentsInProcessError.new("Cannot stop - 41 documents still processing") do
      alice.stop
    end
    assert alice.stopping?

    expect_alice_stopping_finds_documents
    @db_cleanup_utility_action.try_to_move_stopping_workflows_to_stopped

    assert alice.stopping?
  end

  def test_reset_expired_locks
    coll1 = mock
    coll2 = mock
    Armagh::Connection.expects( :all_document_collections ).returns( [ coll1, coll2 ])
    Armagh::Document.expects( :force_reset_expired_locks ).with( collection: coll1 )
    Armagh::Document.expects( :force_reset_expired_locks ).with( collection: coll2 )

    Armagh::ActionStateDocument.expects(:force_reset_expired_locks)
    Armagh::TriggerManagerSemaphoreDocument.expects(:force_reset_expired_locks)

    @db_cleanup_utility_action.reset_expired_locks
  end
end