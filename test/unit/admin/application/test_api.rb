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
require_relative '../../../helpers/mock_logger'
require_relative '../../../../lib/environment'
Armagh::Environment.init

require_relative '../../../../lib/admin/application/api'
require_relative '../../../../lib/connection'
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
  end

  def good_alice_in_db
    @alice = Armagh::Actions::Workflow.create(@config_store, 'alice', notify_to_refresh: @workflow_set )
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
    @fred_workflow_actions_config_values.each do |type,action_config_values|
      @fred.create_action_config(type, action_config_values)
    end
    @fred
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

  def test_get_workflows
    good_alice_in_db
    good_fred_in_db
    expect_alice_docs_in_db
    expect_fred_docs_in_db

    expected_result = [{"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41}, {"name"=>"fred", "run_mode"=>"stop", "retired"=>false, "working_docs_count"=>40, "failed_docs_count"=>10, "published_pending_consume_docs_count"=>0, "docs_count"=>50}]

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


    expected_result = {"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41}
    assert_equal expected_result, @api.get_workflow_status( 'alice' )
  end

  def test_new_workflow
    params = @api.new_workflow
    assert_equal 'workflow:run_mode|workflow:retired', params.collect{ |p| "#{p['group']}:#{p['name']}" }.join('|')
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
    expected_response = {"name"=>test_wf_name, "run_mode"=>"stop", "retired"=>false, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0}
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
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil},
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"ComtexCollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"Comtex", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"fred"},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>nil, 'default'=>Armagh::Documents::DocSpec.new( "__COLLECT__", 'ready'), "valid_state"=>"ready"},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"]},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"]},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>nil}
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
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *"},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false},
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"ComtexCollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_freddocs_from_source"},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>false},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"Comtex", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"fred"},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>Armagh::Documents::DocSpec.new( '__COLLECT__', 'ready' ), "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new('__COLLECT__collect_freddocs_from_source', 'ready'), "valid_state"=>"ready"},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("a_freddoc", 'ready'), "valid_states"=>["ready", "working"]},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("b_freddocs_aggr", "ready"), "valid_states"=>["ready", "working"]},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6},
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
        {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"ComtexCollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_alicedocs_from_source"},
        {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>false},
        {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"Comtex", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"alice"},
        {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *"},
        {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false},
        {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>Armagh::Documents::DocSpec.new("__COLLECT__", "ready"), "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("__COLLECT__collect_alicedocs_from_source","ready"), "valid_state"=>"ready"},
        {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>"type validation failed: value cannot be nil", "value"=>nil, "valid_states"=>["ready", "working"]},
        {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>Armagh::Documents::DocSpec.new("b_alicedocs_aggr_big", "ready"), "valid_states"=>["ready", "working"]},
        {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6}
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
            'schedule' => '7 * * * *'
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

    defined_classes = []
    defined_actions.each {|_t, classes| defined_classes.concat classes}

    assert_empty(global_actions - defined_classes)
    assert_empty(defined_classes - global_actions)
  end

  def test_get_action_super
    assert_equal('Collect', @api.get_action_super(Armagh::StandardActions::TATestCollect))
    assert_equal('Collect', @api.get_action_super(Armagh::StandardActions::ChildCollect))
    assert_raise(RuntimeError.new('Unexpected action type: Hash')){@api.get_action_super(Hash)}
  end

end
