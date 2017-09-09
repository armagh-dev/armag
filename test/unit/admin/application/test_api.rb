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
require_relative '../../../helpers/armagh_test'
require_relative '../../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../../lib/armagh/admin/application/api'
require_relative '../../../../lib/armagh/connection'
require_relative '../../../../test/helpers/workflow_generator_helper'

require 'armagh/actions'

require 'test/unit'
require 'mocha/test_unit'

require 'facets/kernel/constant'

module Armagh
  module StandardActions
    class TATestCollect < Actions::Collect
      define_parameter name: 'host', type: 'populated_string', required: true, default: 'fredhost', description: 'desc'
    end
  end
end

module Armagh
  module StandardActions
    class ChildCollect < TATestCollect
    end
  end
end


class TestAdminApplicationAPI < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @logger = mock_logger
    Armagh::Connection.stubs(:require_connection)
    @api = Armagh::Admin::Application::API.instance
    @config_store = []
    Armagh::Connection.stubs(:config).returns(@config_store)
    assert_equal Armagh::Connection.config, @config_store
    @base_values_hash = {
        'type' => 'Armagh::StandardActions::TATestCollect',

        'output' => {'docspec' => Armagh::Documents::DocSpec.new('dansdoc', Armagh::Documents::DocState::READY)},
        'collect' => {'schedule' => '0 * * * *', 'archive' => false}
    }
    @alice_workflow_config_values = {'workflow'=>{'name'=>'alice'}}
    @alice_workflow_actions_config_values = WorkflowGeneratorHelper.workflow_actions_config_values_with_divide( 'alice' )
    @fred_workflow_config_values = {'workflow'=>{'name' => 'fred'}}
    @fred_workflow_actions_config_values  = WorkflowGeneratorHelper.workflow_actions_config_values_no_divide('fred')
    @remote_user = mock('remote_user')
    set_remote_user_roles([Armagh::Authentication::Role::USER_ADMIN, Armagh::Authentication::Role::USER])
  end

  def set_remote_user_roles(roles)
    @remote_user.unstub(:has_role?)
    @remote_user.stubs(:roles).returns(roles)
    @remote_user.stubs(:has_role?).returns(false)
    @remote_user.roles.each{|r| @remote_user.stubs(:has_role?).with(r).returns(true)}
  end

  def good_alice_in_db
    @alice = Armagh::Actions::Workflow.create(@config_store, 'alice', notify_to_refresh: @workflow_set )
    @alice.unused_output_docspec_check = false
    @alice_workflow_actions_config_values.each do |type,action_config_values|
      @alice.create_action_config(type, action_config_values)
    end
    @alice
  end

  def bad_alice_in_db
    good_alice_in_db
    WorkflowGeneratorHelper.break_array_config_store( @config_store, 'alice' )
  end

  def good_fred_in_db
    @fred = Armagh::Actions::Workflow.create(@config_store, 'fred', notify_to_refresh: @workflow_set )
    @fred.unused_output_docspec_check = false
    @fred_workflow_actions_config_values.each do |type,action_config_values|
      @fred.create_action_config(type, action_config_values)
    end
    @fred
  end

  def agent_statuses
    [
        {'_id' => 'agent-1', 'hostname' => 'host1', 'status' => 'running', 'running_since' => Time.at(0), 'last_updated' => Time.at(1000)},
        {'_id' => 'agent-2', 'hostname' => 'host1', 'status' => 'idle', 'idle_since' => Time.at(100), 'last_updated' => Time.at(1000), 'task' => {'document' => 'doc1', 'action' => 'action1'}},
        {'_id' => 'agent-1', 'hostname' => 'host2', 'status' => 'idle', 'idle_since' => Time.at(0), 'last_updated' => Time.at(1000)},
        {'_id' => 'agent-2', 'hostname' => 'host2', 'status' => 'idle', 'idle_since' => Time.at(100), 'last_updated' => Time.at(1000)}
    ]
  end

  def launcher_statuses
    [
        {'_id' => 'host1', 'status' => 'running', 'versions' => {'armagh' => '1.0.0', 'actions' => {'standard' => '1.0.1', 'armagh_test' => '1.0.2'}}, 'last_updated' => Time.at(1000)},
        {'_id' => 'host2', 'status' => 'running', 'versions' => {'armagh' => '2.0.0', 'actions' => {'standard' => '2.0.1', 'armagh_test' => '2.0.2'}}, 'last_updated' => Time.at(1000)}
    ]
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

  def expect_fred_docs_in_db

    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .with(["a_freddoc", "b_freddoc"])
        .returns( {
                      'documents' => { 'a_alicedoc:ready'=>9, 'b_alicedocs_aggr:ready'=>20, 'a_freddoc:ready'=>40 },
                      'failures'   => {'a_alicedoc:ready'=>3, 'a_freddoc:ready' => 10 },
                      'a_alicedoc' => {'a_alicedoc:published'=>4},
                      'b_alicedoc' => {'b_alicedoc:published'=>5}
                  })
  end

  def test_check_params
    params = {
        'one' => 1,
        'two' => 2,
        'three' => 3
    }
    assert_true @api.check_params(params, 'one')
    assert_true @api.check_params(params, %w(one two))
    assert_true @api.check_params(params, %w(one two three))
    assert_raise(Armagh::Admin::Application::APIClientError.new("A parameter named 'four' is missing but is required.")){@api.check_params(params, %w(one two three four))}
  end

  def test_get_agent_status
    agent_status = agent_statuses

    Armagh::Status::AgentStatus.expects(:find_all).with(raw: true).returns(agent_status)
    assert_equal(agent_status, @api.get_agent_status)
  end

  def test_get_launcher_status
    launcher_status = launcher_statuses
    Armagh::Status::LauncherStatus.expects(:find_all).with(raw: true).returns(launcher_status)
    assert_equal(launcher_status, @api.get_launcher_status)
  end

  def test_get_status
    expected = [
        {
            '_id' => 'host1',
            'agents' => [
                {
                    '_id' => 'agent-1',
                    'hostname' => 'host1',
                    'last_updated' => Time.at(1000),
                    'running_since' => Time.at(0),
                    'status' => 'running'
                },
                {
                    '_id' => 'agent-2',
                    'hostname' => 'host1',
                    'idle_since' => Time.at(100),
                    'last_updated' => Time.at(1000),
                    'status' => 'idle',
                    'task' => {
                        'action' => 'action1',
                        'document' => 'doc1'
                    }
                }
            ],
            'last_updated' => Time.at(1000),
            'status' => 'running',
            'versions' => {
                'actions' => {
                    'armagh_test' => '1.0.2',
                    'standard' => '1.0.1'
                },
                'armagh' => '1.0.0'
            }
        },
        {
            '_id' => 'host2',
            'agents' => [
                {
                    '_id' => 'agent-1',
                    'hostname' => 'host2',
                    'idle_since' => Time.at(0),
                    'last_updated' => Time.at(1000),
                    'status' => 'idle'},
                {
                    '_id' => 'agent-2',
                    'hostname' => 'host2',
                    'idle_since' => Time.at(100),
                    'last_updated' => Time.at(1000),
                    'status' => 'idle'}],
            'last_updated' => Time.at(1000),
            'status' => 'running',
            'versions' => {
                'actions' => {
                    'armagh_test' => '2.0.2',
                    'standard' => '2.0.1'
                },
                'armagh' => '2.0.0'
            }
        }
    ]

    @api.expects(:get_agent_status).returns(agent_statuses)
    @api.expects(:get_launcher_status).returns(launcher_statuses)
    

    assert_equal expected, @api.get_status
  end

  def test_get_workflows
    good_alice_in_db
    good_fred_in_db
    expect_alice_docs_in_db
    expect_fred_docs_in_db

    expected_result = [{"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41}, {"name"=>"fred", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>40, "failed_docs_count"=>10, "published_pending_consume_docs_count"=>0, "docs_count"=>50}]

    assert_equal expected_result, @api.get_workflows
  end

  def test_with_workflow
    good_alice_in_db
    @api.with_workflow('alice') do |wf|
      assert 'alice', wf.name
    end
  end

  def test_with_workflow_doesnt_exist
    good_alice_in_db
    e = assert_raises Armagh::Admin::Application::APIClientError do
      @api.with_workflow('imaginary'){ |wf| }
    end
    assert_equal 'Workflow imaginary not found', e.message
  end

  def test_with_workflow_no_name
    good_alice_in_db
    e = assert_raises Armagh::Admin::Application::APIClientError do
      @api.with_workflow(''){ |wf| }
    end
    assert_equal 'Provide a workflow name', e.message
  end

  def test_get_workflow_status
    good_alice_in_db
    expect_alice_docs_in_db
    good_fred_in_db


    expected_result = {"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41}
    assert_equal expected_result, @api.get_workflow_status( 'alice' )
  end

  def test_new_workflow
    params = @api.new_workflow
    assert_equal 'workflow:run_mode|workflow:retired|workflow:unused_output_docspec_check', params.collect{ |p| "#{p['group']}:#{p['name']}" }.join('|')
    assert_equal [], params.collect{ |p| p['value'] }.compact
  end

  def test_create_workflow

    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .with([])
        .returns( {
                      'documents' => { },
                      'failures'   => { }
                  })

    test_wf_name = 'new_workflow'

    wf = @api.create_workflow( { 'workflow' => { 'name' => test_wf_name }})
    assert_equal test_wf_name, wf.name
    expected_response = {"name"=>test_wf_name, "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>true, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0}
    assert_equal expected_response,@api.get_workflow_status( test_wf_name )
  end

  def test_create_workflow_no_name
    good_alice_in_db
    good_fred_in_db

    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.create_workflow( {} )
    end
    assert_equal 'name cannot be nil', e.message
  end

  def test_create_workflow_duplicate_name_same_case
    good_alice_in_db

    e = assert_raises( Armagh::Actions::WorkflowConfigError ) do
      @api.create_workflow( { 'workflow' => { 'name' => 'alice' }})
    end
    assert_equal 'Workflow name already in use', e.message
  end

  def test_create_workflow_duplicate_name_different_case
    good_alice_in_db

    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.create_workflow( { 'workflow' => { 'name' => 'aLiCe' }})
    end
    assert_equal 'Name already in use', e.message
  end

  def test_run_workflow
    good_alice_in_db
    good_fred_in_db
    expect_alice_docs_in_db
    assert_nothing_raised do
      @api.run_workflow('alice')
    end

    expect_alice_docs_in_db
    wf = @api.get_workflow_status('alice')
    assert_equal 'run', wf['run_mode']
  end

  def test_finish_workflow
    good_alice_in_db
    good_fred_in_db
    expect_alice_docs_in_db
    @api.run_workflow('alice')
    assert_nothing_raised do
      expect_alice_docs_in_db
      @api.finish_workflow('alice')
    end

    expect_alice_docs_in_db
    wf = @api.get_workflow_status('alice')
    assert_equal 'finish', wf['run_mode']
  end

  def test_stop_workflow
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    expect_no_alice_docs_in_db

    @api.finish_workflow('alice')
    assert_nothing_raised do
      @api.stop_workflow('alice')
    end
  end

  def test_stop_workflow_running
    good_alice_in_db
    expect_alice_docs_in_db

    @api.run_workflow('alice')

    expect_no_alice_docs_in_db
    assert_nothing_raised do
      @api.stop_workflow('alice')
    end
    wf_status = @api.get_workflow_status('alice')
    assert_equal 'finish', wf_status['run_mode']
  end

  def test_stop_workflow_docs_still
    good_alice_in_db
    expect_alice_docs_in_db

    @api.run_workflow('alice')
    expect_alice_docs_in_db
    @api.finish_workflow('alice')
    e = assert_raises Armagh::Admin::Application::APIClientError do
      expect_alice_docs_in_db
      @api.stop_workflow('alice')
    end
    assert_equal 'Cannot stop - 41 documents still processing', e.message

    expect_alice_docs_in_db
    wf_status = @api.get_workflow_status('alice')
    assert_equal 'finish', wf_status['run_mode']
  end

  def test_get_workflow_actions
    good_alice_in_db
    actions = nil
    assert_nothing_raised do
      actions = @api.get_workflow_actions('alice')
    end
    expected_action_names = @alice_workflow_actions_config_values.collect{ |_k,cv| cv.dig('action','name')}.sort
    assert_equal expected_action_names, actions.collect{|h| h['name']}.sort
    assert_equal [true], actions.collect{ |h| h['valid'] }.uniq
    assert_equal [false], actions.collect{ |h| h['active'] }.uniq
    actions.each do |action|
      assert_equal action['supertype'], eval(action['type']).superclass.to_s
      assert action['input_docspec']
    end
    assert_equal %w(a_alicedoc:ready b_alicedocs_aggr_big:ready b_alicedocs_aggr:ready a_alicedoc:published b_alicedoc:published b_alicedoc:ready b_aliceconsume_out_doc:ready a_alicedoc_out:ready).sort,
                 actions.collect{ |a| a['output_docspecs']}.compact.flatten.uniq.sort
    tss = actions.collect{ |h| h['last_updated']}.sort
    assert_in_delta Time.now.to_f, tss.min, 5
    assert_in_delta Time.now.to_f, tss.max, 5
  end

  def test_get_workflow_actions_bad_alice
    bad_alice_in_db
    actions = nil
    assert_nothing_raised do
      actions = @api.get_workflow_actions('alice')
    end
    expected_action_names = @alice_workflow_actions_config_values.collect{ |_k,cv| cv.dig('action','name')}.sort
    assert_equal expected_action_names, actions.collect{|h| h['name']}.sort
    assert_equal 2, actions.select{ |h| !h['valid'] }.length
    assert_equal [false], actions.collect{ |h| h['active'] }.uniq
    actions.each do |action|
      assert_equal action['supertype'], eval(action['type']).superclass.to_s
      assert  action['input_docspec']
    end
    assert_equal %w(b_alicedocs_aggr:ready a_alicedoc:published b_alicedoc:published b_alicedoc:ready b_alicedocs_aggr_big:ready b_aliceconsume_out_doc:ready a_alicedoc_out:ready).sort,
                 actions.collect{ |a| a['output_docspecs']}.compact.flatten.uniq.sort
    tss = actions.select{ |h| h['valid']}.collect{ |h| h['last_updated']}.sort
    assert_in_delta Time.now.to_f, tss.min, 5
    assert_in_delta Time.now.to_f, tss.max, 5
  end

  def test_get_workflow_actions_no_workflow
    good_alice_in_db
    e = assert_raises( Armagh::Admin::Application::APIClientError) do
      @api.get_workflow_actions('guessagain')
    end
    assert_equal 'Workflow guessagain not found', e.message
  end


  def test_get_workflow_action_status
    good_alice_in_db
    action_status = nil
    assert_nothing_raised do
      action_status = @api.get_workflow_action_status( 'alice', 'collect_alicedocs_from_source')
    end
    ts = action_status.delete 'last_updated'
    expected_residual_status = {
        "name"=>"collect_alicedocs_from_source",
        "valid"=>true,
        "active"=>false,
        "type" => "Armagh::StandardActions::TWTestCollect",
        "supertype"=> "Armagh::Actions::Collect",
        "input_docspec"   => "__COLLECT__collect_alicedocs_from_source:ready",
        "output_docspecs" => [ "a_alicedoc:ready", "b_alicedocs_aggr_big:ready"] }
    assert_equal expected_residual_status, action_status
    assert_in_delta Time.now.to_f, ts, 5
  end

  def test_get_workflow_action_status_no_workflow
    good_alice_in_db
    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.get_workflow_action_status('nope','nuhuh')
    end
    assert_equal 'Workflow nope not found', e.message
  end

  def test_get_workflow_action_status_no_action
    good_alice_in_db
    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.get_workflow_action_status( 'alice', 'doesntlivehereanymore')
    end
    assert_equal 'Workflow alice has no doesntlivehereanymore action', e.message
  end

  def test_get_workflow_action_status_bad_action
    bad_alice_in_db
    action_status = @api.get_workflow_action_status( 'alice', 'collect_alicedocs_from_source')
    expected_action_status = {
        "name"=>"collect_alicedocs_from_source",
        "valid"=>false,
        "active"=>false,
        "last_updated"=>"",
        "type"=>"Armagh::StandardActions::TWTestCollect",
        "supertype"=>"Armagh::Actions::Collect",
        "input_docspec" => "__COLLECT__collect_alicedocs_from_source:ready",
        "output_docspecs" => ["b_alicedocs_aggr_big:ready"]}
    assert_equal expected_action_status, action_status
  end

  def test_new_workflow_action_config
    good_fred_in_db
    config_hash = @api.new_workflow_action_config( 'fred', 'Armagh::StandardActions::TWTestCollect')
    assert_equal 'Armagh::StandardActions::TWTestCollect', config_hash['type']
    params = config_hash['parameters']
    params.sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
    expected_params =[
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
        {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"fred", "options"=>nil},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>nil, 'default'=>Armagh::Documents::DocSpec.new( "__COLLECT__", 'ready'), "valid_state"=>"ready", "options"=>nil},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil}
    ].sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}

    assert_equal expected_params, params
  end

  def test_create_workflow_action_config
    good_fred_in_db
    new_consume_config_values = Armagh::StandardActions::TWTestConsume.make_config_values(
        action_name: "consume_a_freddoc_new",
        input_doctype: "a_freddoc",
        output_doctype: "a_freddoc_out"
    )
    assert_nothing_raised do
      @api.create_workflow_action_config( 'fred', 'Armagh::StandardActions::TWTestConsume',new_consume_config_values )
    end

    fred_actions = nil
    assert_nothing_raised do
      fred_actions = @api.get_workflow_actions( 'fred' )
    end
    assert_equal 8, fred_actions.length
    expected_new_action_residual_status = {
        "name"=>"consume_a_freddoc_new",
        "valid"=>true,
        "active"=>false,
        "type" => "Armagh::StandardActions::TWTestConsume",
        "supertype" => "Armagh::Actions::Consume",
        "input_docspec" => "a_freddoc:published",
        "output_docspecs" => ["a_freddoc_out:ready"],
    }
    new_action_status = @api.get_workflow_action_status( 'fred', 'consume_a_freddoc_new')
    ts = new_action_status.delete 'last_updated'
    assert_equal expected_new_action_residual_status, new_action_status
    assert_in_delta Time.now.to_f, ts.to_f, 2
  end

  def test_create_workflow_action_config_running
    good_fred_in_db
    expect_fred_docs_in_db
    @fred.run

    actions_status = @api.get_workflow_actions('fred').collect{ |h| h['active']}.uniq
    assert_equal [true], actions_status

    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.create_workflow_action_config( 'fred', 'nuhuh', {})
    end
    assert_equal 'Stop workflow before making changes', e.message
  end

  def test_get_workflow_action_description
    good_fred_in_db
    expected_action_config_params = [
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *", "options"=>nil},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_freddocs_from_source", "options"=>nil},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"fred", "options"=>nil},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>Armagh::Documents::DocSpec.new( '__COLLECT__', 'ready' ), "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new('__COLLECT__collect_freddocs_from_source', 'ready'), "valid_state"=>"ready", "options"=>nil},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("a_freddoc", 'ready'), "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("b_freddocs_aggr", "ready"), "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6, "options"=>nil},
        {"group"=>'action', "error"=>nil}, {"group"=>'collect', "error"=>nil}].sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}

    config_hash = nil
    assert_nothing_raised do
      config_hash = @api.get_workflow_action_description( 'fred', 'collect_freddocs_from_source' )
    end
    assert_equal "Armagh::StandardActions::TWTestCollect", config_hash['type']
    config_params = config_hash['parameters']
    config_params.sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
    assert_equal expected_action_config_params, config_params
  end

  def test_get_workflow_action_description_invalid
    bad_alice_in_db
    expected_action_config_params = [
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_alicedocs_from_source", "options"=>nil},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"alice", "options"=>nil},
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *", "options"=>nil},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>Armagh::Documents::DocSpec.new("__COLLECT__", "ready"), "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("__COLLECT__collect_alicedocs_from_source","ready"), "valid_state"=>"ready", "options"=>nil},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>"type validation failed: value cannot be nil", "value"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("b_alicedocs_aggr_big", "ready"), "valid_states"=>["ready", "working"], "options"=>nil},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6, "options"=>nil}
    ].sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}

    config_hash = nil
    assert_nothing_raised do
      config_hash = @api.get_workflow_action_description( 'alice', 'collect_alicedocs_from_source' )
    end
    config_params = config_hash['parameters']
    assert_equal "Armagh::StandardActions::TWTestCollect", config_hash['type']
    config_params.sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
    assert_equal expected_action_config_params, config_params
  end

  def test_get_action_config
    good_fred_in_db
    config_hash = @api.get_workflow_action_config('fred', 'collect_freddocs_from_source')
    expected = {
        'action' => {
            'active' => 'false',
            'name' => 'collect_freddocs_from_source',
            'workflow' => 'fred'
        },
        'collect' => {
          'archive' => 'false',
          'schedule' => '7 * * * *',
          'decompress' => 'false'
        },
        'input' => {
            'docspec' => '__COLLECT__collect_freddocs_from_source:ready'
        },
        'output' => {
            'docspec' => 'a_freddoc:ready',
            'docspec2' => 'b_freddocs_aggr:ready'},
        'tw_test_collect' => {
            'count' => '6'
        },
        'type' => 'Armagh::StandardActions::TWTestCollect'
    }
    assert_equal(expected, config_hash)
  end

  def test_get_action_config_invalid
    bad_alice_in_db
    assert_nil @api.get_workflow_action_config('alice', 'collect_alicedocs_from_source')
  end

  def test_update_workflow_action_config
    good_alice_in_db
    collect_action_hash = @api.get_workflow_action_description( 'alice', 'collect_alicedocs_from_source')
    assert_equal "Armagh::StandardActions::TWTestCollect", collect_action_hash['type']
    collect_action_params = collect_action_hash['parameters']

    collect_schedule_param = collect_action_params.find{ |p| p['group']=='collect' && p['name']=='schedule'}
    collect_schedule_param['value'] = '29 * * * *'
    collect_action_config_values = {}
    collect_action_params.each do |p|
      if p['group'] && p['name'] && p['value']
        collect_action_config_values[ p['group']] ||= {}
        collect_action_config_values[ p['group']][p['name']] = p['value']
      end
    end
    @api.update_workflow_action_config( 'alice', 'collect_alicedocs_from_source', collect_action_config_values )
  end

  def test_update_workflow_action_config_running
    good_alice_in_db
    expect_no_alice_docs_in_db
    @alice.run

    actions_status = @api.get_workflow_actions('alice').collect{ |h| h['active']}.uniq
    assert_equal [true], actions_status

    e = assert_raises( Armagh::Admin::Application::APIClientError ) do
      @api.update_workflow_action_config( 'alice', 'collect_alicedocs_from_source', {})
    end
    assert_equal 'Stop workflow before making changes', e.message
  end

  def test_trigger_collect
    collection_trigger = mock('collection trigger')
    collection_trigger.expects(:trigger_individual_collection).with(kind_of(Configh::Configuration))
    Armagh::Utils::CollectionTrigger.expects(:new).returns(collection_trigger)
    good_alice_in_db
    expect_no_alice_docs_in_db
    @alice.run

    collect_name = nil
     @alice_workflow_actions_config_values.each do |type, config|
       if constant(type) < Armagh::Actions::Collect
         collect_name = config['action']['name']
         break
       end
     end

    assert_not_nil collect_name, 'No Collects were configured'
    assert_true @api.trigger_collect(collect_name)
  end

  def test_trigger_collect_none
    e = Armagh::Admin::Application::APIClientError.new('Action no_action is not an active action.')
    assert_raise(e){@api.trigger_collect('no_action')}
  end

  def test_trigger_collect_not_collect
    good_alice_in_db
    expect_no_alice_docs_in_db
    @alice.run

    collect_name = nil
    @alice_workflow_actions_config_values.each do |type, config|
      unless constant(type) < Armagh::Actions::Collect
        collect_name = config['action']['name']
        break
      end
    end

    assert_not_nil collect_name, 'No non-collects were configured'

    e = Armagh::Admin::Application::APIClientError.new("Action #{collect_name} is not a collect action.")
    assert_raise(e){@api.trigger_collect(collect_name)}
  end

  def test_get_defined_actions
    global_actions =  Armagh::Actions.defined_actions.collect{|c|c.to_s}
    defined_actions = @api.get_defined_actions

    assert_kind_of Hash, defined_actions
    assert_equal %w(Collect Consume Divide Publish Split), defined_actions.keys.sort

    defined_classes_names = defined_actions.collect {|_t, classes| classes.collect{ |c| c['name']}}.flatten
    defined_classes_descriptions = defined_actions.collect{ |_t, classes| classes.collect{ |c| c['description']}}.flatten

    assert_empty(global_actions - defined_classes_names)
    assert_empty(defined_classes_names - global_actions)
    assert_equal( defined_classes_names.length, defined_classes_descriptions.compact.length)
  end

  def test_get_action_super
    assert_equal('Collect', @api.get_action_super(Armagh::StandardActions::TATestCollect))
    assert_equal('Collect', @api.get_action_super(Armagh::StandardActions::ChildCollect))
    e = Armagh::Utils::ActionHelper::ActionClassError.new('Hash is not a known action type.')
    assert_raise(e){@api.get_action_super(Hash)}
  end

  def test_private_get_action_class_from_type
    Armagh::Actions.expects(:defined_actions).once.returns(['Armagh::Some::Type'])
    result = @api.send(:get_action_class_from_type, 'Armagh::Some::Type')
    assert_equal 'Armagh::Some::Type', result
  end

  def test_private_get_action_class_from_type_does_not_exist
    Armagh::Actions.expects(:defined_actions).once.returns(['Armagh::Some::Type'])
    e = assert_raise Armagh::Admin::Application::APIClientError do
      @api.send(:get_action_class_from_type, 'Does::Not::Exist')
    end
    assert_equal 'Action type Does::Not::Exist does not exist', e.message
  end

  def test_get_action_test_callbacks
    type = 'Armagh::Some::Type'
    type_class = mock('type_class')
    type_class.expects(:defined_group_test_callbacks).once.returns([stub(group: 'group', callback_method: 'method')])
    @api.expects(:get_action_class_from_type).once.returns(type_class)
    result = @api.get_action_test_callbacks(type)
    expected = [{class: type_class, group: 'group', method: 'method'}]
    assert_equal expected, result
  end

  def test_invoke_action_test_callback
    type_class = mock('type_class')
    mod = mock('module')
    mod.expects(:method).once.returns('blah')
    mod.expects(:create_configuration).once.returns('config')
    type_class.expects(:included_modules).once.returns([mod])
    @api.expects(:get_action_class_from_type).once.returns(type_class)
    data = {
      'type'   => 'type_class',
      'group'  => 'group',
      'method' => 'method'
    }
    result = @api.invoke_action_test_callback(data)
    assert_equal 'blah', result
  end

  def test_invoke_action_test_callback_failed_to_instantiate_test_config
    type_class = mock('type_class')
    mod = mock('module')
    mod.stubs(:method).returns('blah')
    mod.expects(:create_configuration).once.raises(RuntimeError.new('some error'))
    type_class.expects(:included_modules).once.returns([mod])
    @api.expects(:get_action_class_from_type).once.returns(type_class)
    data = {
      'type'   => 'type_class',
      'group'  => 'group',
      'method' => 'method'
    }
    result = @api.invoke_action_test_callback(data)
    assert_equal 'Failed to instantiate test configuration: some error', result
  end

  def test_get_users
    result = [1,2,3]
    Armagh::Authentication::User.expects(:find_all).returns(result)
    assert_equal(result, @api.get_users)

    Armagh::Authentication::User.expects(:find_all).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.get_users}
  end

  def test_get_user
    user = mock
    Armagh::Authentication::User.expects(:find).with('id').returns(user)
    assert_equal(user, @api.get_user('id'))

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.get_user('none')}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.get_user('error')}
  end

  def test_create_user
    fields = {
        'username' => 'username',
        'password' => '12345',
        'name' => 'name',
        'email' => 'email'
    }

    Armagh::Authentication::User.expects(:create).with(
        username: fields['username'],
        password: fields['password'],
        name: fields['name'],
        email: fields['email']
    )
    @api.create_user(fields)

    Armagh::Authentication::User.expects(:create).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.create_user(fields)}
  end

  def test_update_user_by_id
    fields = {
        'username' => 'username',
        'password' => '12345',
        'name' => 'name',
        'email' => 'email'
    }

    user = mock('user')

    Armagh::Authentication::User.expects(:update).with(
        id: 'id',
        username: fields['username'],
        password: fields['password'],
        name: fields['name'],
        email: fields['email']
    ).returns(user)
    @api.update_user_by_id('id', fields)

    Armagh::Authentication::User.expects(:update).returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID id not found.')){@api.update_user_by_id('id', fields)}

    Armagh::Authentication::User.expects(:update).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.update_user_by_id('id', fields)}
  end

  def test_update_user
    fields = {
      'username' => 'username',
      'password' => '12345',
      'name' => 'name',
      'email' => 'email'
    }

    user = mock('user')

    user.expects(:update).with(
      username: fields['username'],
      password: fields['password'],
      name: fields['name'],
      email: fields['email']
    ).returns(user)
    user.expects(:save)

    @api.update_user(user, fields)

    user.expects(:update).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.update_user(user, fields)}
  end

  def test_delete_user
    user = mock
    user.expects(:delete)
    Armagh::Authentication::User.expects(:find).with('id').returns(user)
    assert_true@api.delete_user('id')

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.delete_user('none')}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.delete_user('error')}
  end

  def test_user_join_group
    user = mock 'user'
    user.stubs(:all_roles).returns({'self' => []})
    group = mock 'group'
    group.stubs(:name).returns('Group123')
    group.stubs(:roles).returns([Armagh::Authentication::Role::USER_ADMIN])

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(4)
    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)

    user.expects(:join_group).with(group)
    user.expects(:save)
    assert_true @api.user_join_group('user_id', 'group_id', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.user_join_group('none', 'group_id', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.user_join_group('user_id', 'none', @remote_user)}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_join_group('error', 'group_id', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Cannot add user user_id to group group_id. Doing so would grant the following roles, which you don't have: User Admin.")){ @api.user_join_group('user_id', 'group_id', @remote_user)}

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN]})
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    group.expects(:add_user).with(user)
    group.expects(:save)
    assert_true @api.group_add_user('group_id', 'user_id', @remote_user)
  end

  def test_user_leave_group
    user = mock 'user'
    group = mock 'group'
    group.stubs(:name).returns('Group123')
    group.stubs(:roles).returns([Armagh::Authentication::Role::USER_ADMIN])
    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'Group123' => [Armagh::Authentication::Role::RESOURCE_ADMIN]})

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(4)
    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)

    user.expects(:leave_group).with(group)
    user.expects(:save)
    assert_true @api.user_leave_group('user_id', 'group_id', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.user_leave_group('none', 'group_id', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.user_leave_group('user_id', 'none', @remote_user)}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_leave_group('error', 'group_id', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'Group123' => [Armagh::Authentication::Role::USER_ADMIN]})
    user.expects(:leave_group).with(group)
    user.expects(:save)
    assert_true @api.user_leave_group('user_id', 'group_id', @remote_user)

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.stubs(:all_roles).returns({'self' => [], 'Group123' => [Armagh::Authentication::Role::USER_ADMIN]})
    assert_raise(Armagh::Admin::Application::APIClientError.new("Unable to remove user user_id from group group_id. Doing so would remove the following roles, which you don't have: User Admin.")){ @api.user_leave_group('user_id', 'group_id', @remote_user)}
  end

  def test_user_add_role
    user = mock 'user'
    user.stubs(:all_roles).returns({'self' => []})
    role = Armagh::Authentication::Role::USER_ADMIN

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(4)
    Armagh::Authentication::Role.expects(:find).with('role_key').returns(role).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Role.expects(:find).with('none').returns(nil)

    user.expects(:add_role).with(role)
    user.expects(:save)
    assert_true @api.user_add_role('user_id', 'role_key', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.user_add_role('none', 'role_key', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new("Role 'none' not found.")){@api.user_add_role('user_id', 'none', @remote_user)}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_add_role('error', 'role_key', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Cannot add role User Admin to user user_id. Doing so would grant the following roles, which you don't have: User Admin.")){ @api.user_add_role('user_id', 'role_key', @remote_user)}

    user.stubs(:all_roles).returns({'self' => [], 'group' => [role]})
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.expects(:add_role).with(role)
    user.expects(:save)
    assert_true @api.user_add_role('user_id', 'role_key', @remote_user)
  end

  def test_user_remove_role
    user = mock 'user'
    role = Armagh::Authentication::Role::USER_ADMIN

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'group' => [Armagh::Authentication::Role::RESOURCE_ADMIN]})

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(4)
    Armagh::Authentication::Role.expects(:find).with('role_key').returns(role).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Role.expects(:find).with('none').returns(nil)

    user.expects(:remove_role).with(role)
    user.expects(:save)
    assert_true @api.user_remove_role('user_id', 'role_key', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.user_remove_role('none', 'role_key', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new("Role 'none' not found.")){@api.user_remove_role('user_id', 'none', @remote_user)}

    Armagh::Authentication::User.expects(:find).with('error').raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_remove_role('error', 'role_key', @remote_user)}

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'group' => [Armagh::Authentication::Role::USER_ADMIN]})
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.expects(:remove_role).with(role)
    user.expects(:save)
    assert_true @api.user_remove_role('user_id', 'role_key', @remote_user)

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN]})
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Unable to remove role role_key from user user_id. Doing so would remove the following roles, which you don't have: User Admin.")){ @api.user_remove_role('user_id', 'role_key', @remote_user)}
  end

  def test_user_reset_password
    expected = 'NeWPaSsWoRd'
    user = mock('user')
    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER]})

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(3)

    user.expects(:reset_password).returns(expected)
    assert_equal expected,@api.user_reset_password('user_id', @remote_user)

    user.expects(:reset_password).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_reset_password('user_id', @remote_user)}

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::RESOURCE_ADMIN]})
    user.expects(:reset_password).never
    assert_raise(Armagh::Admin::Application::APIClientError.new("Cannot reset password for user_id. The user has the following roles, which you don't have: Resource Admin.")){@api.user_reset_password('user_id', @remote_user)}
  end

  def test_user_lock
    user = mock('user')

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).twice

    user.expects(:lock).returns(true)
    user.expects(:save)
    assert_true @api.user_lock('user_id')

    user.expects(:lock).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_lock('user_id')}
  end

  def test_user_unlock
    user = mock('user')

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).twice

    user.expects(:unlock).returns(true)
    user.expects(:save)
    assert_true @api.user_unlock('user_id')

    user.expects(:unlock).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_unlock('user_id')}
  end

  def test_user_enable
    user = mock('user')

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).twice

    user.expects(:enable).returns(true)
    user.expects(:save)
    assert_true @api.user_enable('user_id')

    user.expects(:enable).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_enable('user_id')}
  end

  def test_user_disable
    user = mock('user')

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).twice

    user.expects(:disable).returns(true)
    user.expects(:save)
    assert_true @api.user_disable('user_id')

    user.expects(:disable).raises(Armagh::Authentication::User::UserError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.user_disable('user_id')}
  end

  def test_get_groups
    result = [1,2,3,4]
    Armagh::Authentication::Group.expects(:find_all).returns(result)
    assert_equal result, @api.get_groups

    Armagh::Authentication::Group.expects(:find_all).raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.get_groups}
  end

  def test_get_group
    group = mock
    Armagh::Authentication::Group.expects(:find).with('id').returns(group)
    assert_equal(group, @api.get_group('id'))

    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.get_group('none')}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.get_group('error')}
  end

  def test_create_group
    fields = {
        'name' => 'group_name',
        'description' => 'description',
    }
    Armagh::Authentication::Group.expects(:create).with(
        name: fields['name'],
        description: fields['description']
    )
    @api.create_group(fields)

    Armagh::Authentication::Group.expects(:create).raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.create_group(fields)}
  end

  def test_update_group
    fields = {
        'name' => 'group_name',
        'description' => 'description',
    }

    group = mock

    Armagh::Authentication::Group.expects(:update).with(
        id: 'id',
        name: fields['name'],
        description: fields['description']
    ).returns(group)

    assert_equal group, @api.update_group('id', fields)

    Armagh::Authentication::Group.expects(:update).returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID id not found.')){@api.update_group('id', fields)}

    Armagh::Authentication::Group.expects(:update).raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.update_group('id', fields)}
  end

  def test_group_add_role
    group = mock 'group'
    role = Armagh::Authentication::Role::USER

    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)
    Armagh::Authentication::Role.expects(:find).with('role_key').returns(role).times(2)

    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Role.expects(:find).with('none').returns(nil)

    group.expects(:add_role).with(role)
    group.expects(:save)
    assert_true @api.group_add_role('group_id', 'role_key', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.group_add_role('none', 'role_key', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new("Role 'none' not found.")){@api.group_add_role('group_id', 'none', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.group_add_role('error', 'role_key', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER_ADMIN])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Cannot add role User to group group_id. Doing so would grant the following roles, which you don't have: User.")){@api.group_add_role('group_id', 'role_key', @remote_user)}
  end

  def test_group_remove_role
    group = mock 'group'
    role = Armagh::Authentication::Role::USER

    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)
    Armagh::Authentication::Role.expects(:find).with('role_key').returns(role).times(2)

    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Role.expects(:find).with('none').returns(nil)

    group.expects(:remove_role).with(role)
    group.expects(:save)
    assert_true @api.group_remove_role('group_id', 'role_key', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.group_remove_role('none', 'role_key', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new("Role 'none' not found.")){@api.group_remove_role('group_id', 'none', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.group_remove_role('error', 'role_key', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER_ADMIN])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Unable to remove role User from group group_id. Doing so would remove the following roles, which you don't have: User.")){@api.group_remove_role('group_id', 'role_key', @remote_user)}
  end

  def test_group_add_user
    user = mock 'user'
    user.stubs(:all_roles).returns({'self' => []})
    group = mock 'group'
    group.stubs(:name).returns('Group123')
    group.stubs(:roles).returns([Armagh::Authentication::Role::USER_ADMIN])

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(5)
    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)

    group.expects(:add_user).with(user)
    group.expects(:save)
    assert_true @api.group_add_user('group_id', 'user_id', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.group_add_user('none', 'user_id', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.group_add_user('group_id', 'none', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.group_add_user('error', 'user_id', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Cannot add user user_id to group group_id. Doing so would grant the following roles, which you don't have: User Admin.")){ @api.group_add_user('group_id', 'user_id', @remote_user)}

    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN]})
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    group.expects(:add_user).with(user)
    group.expects(:save)
    assert_true @api.group_add_user('group_id', 'user_id', @remote_user)
  end

  def test_group_remove_user
    user = mock 'user'
    group = mock 'group'
    group.stubs(:name).returns('Group123')
    group.stubs(:roles).returns([Armagh::Authentication::Role::USER_ADMIN])
    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'Group123' => [Armagh::Authentication::Role::RESOURCE_ADMIN]})

    Armagh::Authentication::User.expects(:find).with('user_id').returns(user).times(5)
    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group).times(3)

    Armagh::Authentication::User.expects(:find).with('none').returns(nil)
    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)

    group.expects(:remove_user).with(user)
    group.expects(:save)
    assert_true @api.group_remove_user('group_id', 'user_id', @remote_user)

    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.group_remove_user('none', 'user_id', @remote_user)}
    assert_raise(Armagh::Admin::Application::APIClientError.new('User with ID none not found.')){@api.group_remove_user('group_id', 'none', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.group_remove_user('error', 'user_id', @remote_user)}

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.stubs(:all_roles).returns({'self' => [Armagh::Authentication::Role::USER_ADMIN], 'Group123' => [Armagh::Authentication::Role::USER_ADMIN]})
    user.expects(:leave_group).with(group)
    user.expects(:save)
    assert_true @api.user_leave_group('user_id', 'group_id', @remote_user)

    set_remote_user_roles([Armagh::Authentication::Role::USER])
    user.stubs(:all_roles).returns({'self' => [], 'Group123' => [Armagh::Authentication::Role::USER_ADMIN]})
    assert_raise(Armagh::Admin::Application::APIClientError.new("Unable to remove user user_id from group group_id. Doing so would remove the following roles, which you don't have: User Admin.")){ @api.user_leave_group('user_id', 'group_id', @remote_user)}
  end

  def test_delete_group
    group = mock('group')
    group.expects(:delete)
    group.stubs(:roles).returns([Armagh::Authentication::Role::USER_ADMIN])
    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group)
    assert_true@api.delete_group('group_id', @remote_user)

    Armagh::Authentication::Group.expects(:find).with('none').returns(nil)
    assert_raise(Armagh::Admin::Application::APIClientError.new('Group with ID none not found.')){@api.delete_group('none', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('error').raises(Armagh::Authentication::Group::GroupError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError.new('boom')){@api.delete_group('error', @remote_user)}

    Armagh::Authentication::Group.expects(:find).with('group_id').returns(group)
    set_remote_user_roles([Armagh::Authentication::Role::USER])
    assert_raise(Armagh::Admin::Application::APIClientError.new("Unable to remove group group_id. Doing so would remove the following roles, which you don't have: User Admin.")){@api.delete_group('group_id', @remote_user)}
  end

  def test_get_roles
    Armagh::Authentication::Role.expects(:all)
    @api.get_roles
  end

  def test_user_has_document_role
    user = mock('user')
    user.stubs(:username).returns('test_user')

    pub_collection = stub({name: 'documents.test_doc'})
    doc_role = Armagh::Authentication::Role.published_collection_role(pub_collection)

    # has role
    Armagh::Authentication::Role.expects(:find_from_published_doctype).with('test_doc').returns(doc_role)
    user.expects(:has_role?).with(doc_role).returns true
    @api.user_has_document_role(user, 'test_doc')

    # does not have role
    Armagh::Authentication::Role.expects(:find_from_published_doctype).with('test_doc').returns(doc_role)
    user.expects(:has_role?).with(doc_role).returns false
    assert_raise(Armagh::Authentication::AuthenticationError.new('User test_user does not have the required role to access test_doc documents.')){@api.user_has_document_role(user, 'test_doc')}

    Armagh::Authentication::Role.unstub(:find_from_published_doctype)

    # Unknown doc type
    Armagh::Authentication::Role.expects(:find_from_published_doctype).with('invalid').returns(nil)
    user.expects(:has_role?).with(Armagh::Authentication::Role::USER).returns true
    @api.user_has_document_role(user, 'invalid')

    # Unknown doc type without user
    Armagh::Authentication::Role.expects(:find_from_published_doctype).with('invalid').returns(nil)
    user.expects(:has_role?).with(Armagh::Authentication::Role::USER).returns false
    assert_raise(Armagh::Authentication::AuthenticationError.new('User test_user does not have the required role to access invalid documents.')){@api.user_has_document_role(user, 'invalid')}
  end

  def test_init_checks_connection
    Armagh::Connection.unstub(:require_connection)
    Armagh::Connection.expects(:require_connection)
    Armagh::Admin::Application::API.send(:new)
  end

  def test_update_password
    user = mock('user')
    password = 'some_password'
    user.expects(:password=).with(password)
    user.expects(:save)
    @api.update_password(user, password)

    user.expects(:password=).raises(Armagh::Utils::Password::PasswordError.new('boom'))
    assert_raise(Armagh::Admin::Application::APIClientError){@api.update_password(user, 'pass')}
  end
end
