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
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../helpers/workflow_generator_helper'
require_relative '../../../lib/armagh/actions/workflow_set'
require_relative '../../../lib/armagh/connection'
require_relative '../../../lib/armagh/document/document'


require 'armagh/actions'

class TestWorkflowSet < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @config_store = []
    @logger = mock_logger
    @caller = mock

    @alice_workflow_config_values = {'workflow'=>{'name'=>'alice'}}
    @alice_workflow_actions_config_values = WorkflowGeneratorHelper.workflow_actions_config_values_with_divide( 'alice' )
    @fred_workflow_config_values = {'workflow'=>{'name' => 'fred'}}
    @fred_workflow_actions_config_values  = WorkflowGeneratorHelper.workflow_actions_config_values_no_divide('fred')
    @state_coll = mock
    Armagh::Connection.stubs(:config).returns(@state_coll)
  end

  def good_alice_in_db
    @alice = Armagh::Actions::Workflow.create(@config_store, 'alice', notify_to_refresh: @workflow_set )
    @alice.unused_output_docspec_check = false
    @alice_workflow_actions_config_values.each do |type,action_config_values|
      @alice.create_action_config(type, action_config_values)
    end
    @alice
  end

  def good_fred_in_db
    @fred = Armagh::Actions::Workflow.create(@config_store, 'fred', notify_to_refresh: @workflow_set )
    @fred.unused_output_docspec_check = false
    @fred_workflow_actions_config_values.each do |type,action_config_values|
      @fred.create_action_config(type, action_config_values)
    end
    @fred
  end

  def bad_alice_in_db
    good_alice_in_db
    WorkflowGeneratorHelper.break_array_config_store( @config_store, 'alice' )
  end

  def expect_alice_docs_in_db
    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .with(["a_alicedoc", "b_alicedoc"])
        .returns( {
                      'documents' => { 'a_alicedoc:ready'=>9, 'b_alicedocs_aggr:ready'=>20, 'a_freddoc:ready'=>400_000 },
                      'failures'   => {'a_alicedoc:ready'=>3, 'a_freddoc:ready' => 100_000 },
                      'a_alicedoc' => {'a_alicedoc:published'=>4},
                      'b_alicedoc' => {'b_alicedoc:published'=>5}
                  })
  end

  def expect_no_alice_docs_in_db
    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .at_least_once
        .with(["a_alicedoc", "b_alicedoc"])
        .returns( {
                      'documents' => { 'a_freddoc:ready'=>400_000 },
                      'failures'   => {'a_freddoc:ready' => 100_000 },
                      'a_alicedoc' => {},
                      'b_alicedoc' => {}
                  })
  end

  def expect_no_fred_docs_in_db
    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .at_least_once
        .with(["a_freddoc", "b_freddoc"])
        .returns( {
                      'documents' => { },
                      'failures'   => { },
                      'a_alicedoc' => {},
                      'b_alicedoc' => {}
                  })
  end

  def teardown
  end

  def test_refresh_error
    e = assert_raise Armagh::Actions::RefreshError do
      Armagh::Actions::WorkflowSet.send(:new, @config_store, :unknown)
    end
    assert_equal 'refresh called with invalid target: unknown', e.message
  end

  def test_create_workflow
    assert_nothing_raised do
      good_alice_in_db
    end
  end

  def test_for_admin
    good_alice_in_db
    good_fred_in_db

    wf_set = Armagh::Actions::WorkflowSet.for_admin( @config_store )

    assert_equal :admin, wf_set.instance_variable_get('@target')
    assert_equal @config_store, wf_set.instance_variable_get('@config_store')

    alice = wf_set.get_workflow('alice')
    assert_equal 'alice', alice.name
    assert_equal @alice_workflow_actions_config_values.length, alice.valid_action_configs.length

    fred = wf_set.get_workflow('fred')
    assert_equal 'fred', fred.name
  end

  def test_for_admin_with_broken_workflow
    bad_alice_in_db
    good_fred_in_db

    wf_set = Armagh::Actions::WorkflowSet.for_admin( @config_store )

    assert_equal :admin, wf_set.instance_variable_get('@target')
    assert_equal @config_store, wf_set.instance_variable_get('@config_store')

    alice = wf_set.get_workflow('alice')
    assert_equal 'alice', alice.name
    assert_equal @alice_workflow_actions_config_values.length - 2, alice.valid_action_configs.length
    assert_equal 2, alice.invalid_action_configs.length

    fred = wf_set.get_workflow('fred')
    assert_equal 'fred', fred.name
  end

  def test_for_agent
    good_alice_in_db
    good_fred_in_db

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )

    assert_equal :agent, wf_set.instance_variable_get('@target')
    assert_equal @config_store, wf_set.instance_variable_get('@config_store')

    alice = wf_set.get_workflow('alice')
    assert_equal 'alice', alice.name
    assert_equal @alice_workflow_actions_config_values.length, alice.valid_action_configs.length

    fred = wf_set.get_workflow('fred')
    assert_equal 'fred', fred.name

  end

  def test_for_agent_with_broken_workflow
    bad_alice_in_db
    good_fred_in_db

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )

    assert_equal :agent, wf_set.instance_variable_get('@target')
    assert_equal @config_store, wf_set.instance_variable_get('@config_store')

    alice = wf_set.get_workflow('alice')
    assert_equal 'alice', alice.name
    assert_equal @alice_workflow_actions_config_values.length - 2, alice.valid_action_configs.length
    assert_equal 2, alice.invalid_action_configs.length
    e = assert_raises Armagh::Actions::WorkflowActivationError do
      alice.run
    end
    assert_equal 'Workflow not valid', e.message
  end

  def test_list
    good_alice_in_db
    good_fred_in_db
    expect_alice_docs_in_db
    expect_no_fred_docs_in_db
    @alice.run
    @fred.run

    wf_set = nil
    assert_nothing_raised do
      wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    end

    expected = [
      {"name"=>"alice", "run_mode"=>Armagh::Actions::Workflow::RUNNING, "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41, "valid"=>true},
      {"name"=>"fred", "run_mode"=>Armagh::Actions::Workflow::RUNNING, "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0, "valid"=>true}
    ]

    expect_alice_docs_in_db
    expect_no_fred_docs_in_db
    assert_equal expected, wf_set.list_workflows
  end

  def test_instantiate_action_from_config
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )

    action = nil
    action_config = @alice.valid_action_configs.find{ |ac| ac.__name == 'collect_alicedocs_from_source' }
    assert_nothing_raised do
      action = wf_set.instantiate_action_from_config(action_config, @caller, @logger, @state_coll)
    end
    assert_equal Armagh::StandardActions::TWTestCollect, action.class
  end

  def test_instantiate_action_from_config_nil
    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    e = assert_raises( Armagh::Actions::ActionInstantiationError ) do
      wf_set.instantiate_action_from_config( nil, @caller, @logger, @state_coll)
    end
    assert_equal 'Attempt to instantiate nil action config', e.message
  end

  def test_instantiate_action_from_config_not_active
    good_alice_in_db

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )

    action_config = @alice.valid_action_configs.find{ |ac| ac.__name == 'collect_alicedocs_from_source' }
    e = assert_raises Armagh::Actions::ActionInstantiationError do
      wf_set.instantiate_action_from_config(action_config, @caller, @logger, @state_coll)
    end
    assert_equal 'Action not active', e.message
  end

  def test_instantiate_action_from_name
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run

    action = nil
    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    assert_nothing_raised do
      action = wf_set.instantiate_action_named('collect_alicedocs_from_source', @caller, @logger, @state_coll)
    end
    assert_equal Armagh::StandardActions::TWTestCollect, action.class
  end

  def test_instatiate_action_with_bad_name
    good_alice_in_db
    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    e = assert_raises( Armagh::Actions::ActionInstantiationError ) do
      wf_set.instantiate_action_named('i_dont_exist', @caller, @logger, @state_coll)
    end
    assert_equal 'Action i_dont_exist not defined', e.message
  end

  def test_instatiate_action_with_nil_name
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    e = assert_raises( Armagh::Actions::ActionInstantiationError ) do
      wf_set.instantiate_action_named(nil, @caller, @logger, @state_coll)
    end
    assert_equal 'Action name cannot be nil', e.message
  end

  def test_instantiate_action_by_docspec
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run

    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    actions = nil
    actions = wf_set.instantiate_actions_handling_docspec(
        Armagh::Documents::DocSpec.new('b_alicedocs_aggr_big', Armagh::Documents::DocState::READY),
        @caller, @logger, @state_coll )
    assert_equal 'divide_b_alicedocs', actions.first.config.action.name
    assert_equal Armagh::StandardActions::TWTestDivide, actions.first.class
    assert_equal 'split_b_alicedocs', actions.last.config.action.name
    assert_equal Armagh::StandardActions::TWTestSplit, actions.last.class
  end

  def test_actions_names_handling_docspec
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    actions_names = wf_set.actions_names_handling_docspec( Armagh::Documents::DocSpec.new('b_alicedocs_aggr_big', Armagh::Documents::DocState::READY))
    assert_equal ['divide_b_alicedocs', 'split_b_alicedocs'], actions_names
  end

  def test_collect_action_configs
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    wf_set = Armagh::Actions::WorkflowSet.for_agent( @config_store )
    assert_equal [ 'collect_alicedocs_from_source' ], wf_set.collect_action_configs.collect{|ac| ac.action.name}
  end

  def test_workflow_set_create_workflow
    wf_set = Armagh::Actions::WorkflowSet.for_admin(@config_store)
    workflow = {'workflow'=>{'name'=>'new_workflow'}}
    wf_set.create_workflow(workflow)
    result = wf_set.instance_variable_get(:@workflows)['new_workflow']
    assert_equal 'new_workflow', result.name
  end

  def test_workflow_set_create_workflow_config_init_error
    wf_set = Armagh::Actions::WorkflowSet.for_admin(@config_store)
    workflow = {'workflow'=>{'name'=>'new_workflow'}}
    Armagh::Actions::Workflow.expects(:create)
      .once
      .raises(Configh::ConfigInitError, 'some error')
    e = assert_raise Armagh::Actions::WorkflowConfigError do
      wf_set.create_workflow(workflow)
    end
    assert_equal 'some error', e.message
  end

  def test_trigger_collect
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    wf_set = Armagh::Actions::WorkflowSet.for_agent(@config_store)
    action_name = 'collect_alicedocs_from_source'
    action_config = @alice.valid_action_configs.find{ |ac| ac.__name == action_name }
    wf_set.instantiate_action_from_config(action_config, @caller, @logger, @state_coll)
    trigger = mock('trigger')
    trigger.expects(:trigger_individual_collection).once
    require_relative '../../../lib/armagh/utils/collection_trigger'
    Armagh::Utils::CollectionTrigger.expects(:new).once.returns(trigger)
    result = wf_set.trigger_collect(action_name)
    assert_true result
  end

  def test_trigger_collect_empty_action_name
    wf_set = Armagh::Actions::WorkflowSet.for_agent(@config_store)
    e = assert_raise Armagh::Actions::TriggerCollectError do
      wf_set.trigger_collect('')
    end
    assert_equal 'No action name supplied.', e.message
  end

  def test_trigger_collect_action_not_active
    wf_set = Armagh::Actions::WorkflowSet.for_agent(@config_store)
    e = assert_raise Armagh::Actions::TriggerCollectError do
      wf_set.trigger_collect('error_me')
    end
    assert_equal 'Action error_me is not an active action.', e.message
  end

  def test_trigger_collect_action_not_collect
    wf_set = Armagh::Actions::WorkflowSet.for_agent(@config_store)
    action = mock('action')
    action.expects(:__type)
      .once
      .returns(Armagh::Actions::Publish)
    action_config_named = {'error_me'=>action}
    wf_set.instance_variable_set(:@action_config_named, action_config_named)
    e = assert_raise Armagh::Actions::TriggerCollectError do
      wf_set.trigger_collect('error_me')
    end
    assert_equal 'Action error_me is not a collect action.', e.message
  end

end

