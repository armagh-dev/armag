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
require_relative '../../lib/agent/agent'
require_relative '../test_helpers/mock_global_logger'
require_relative '../../lib/agent/agent_status'
require_relative '../../lib/ipc'
require_relative '../../lib/document/document'
require_relative '../../lib/action/action_instance'
require_relative '../../lib/action/action_manager'

require 'mocha/test_unit'
require 'test/unit'
require 'logger'

class TestAgent < Test::Unit::TestCase

  THREAD_SLEEP_TIME = 0.01

  STARTED = []

  def setup
    ArmaghTest.mock_global_logger
    @agent = Armagh::Agent.new
    @backoff_mock = mock('object')
    @agent.instance_variable_set(:@backoff, @backoff_mock)
  end

  def teardown
    @agent.stop
  end

  def test_stop
    @agent.instance_variable_set(:@running, true)
    assert_true @agent.running?
    @agent.stop
    assert_false @agent.running?
  end

  def test_start
    assert_false @agent.running?

    agent_status = Armagh::AgentStatus.new
    agent_status.config = {}
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    Thread.new { @agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true @agent.running?
  end

  def test_start_with_config
    config = {
        'log_level' => Logger::ERROR
    }

    agent_status = mock
    agent_status.stubs(:config).returns(config)

    DRbObject.stubs(:new_with_uri).returns(agent_status)

    assert_not_equal(Logger::ERROR, @agent.instance_variable_get(:@logger).level)
    Thread.new { @agent.start }
    sleep THREAD_SLEEP_TIME
    assert_equal(Logger::ERROR, @agent.instance_variable_get(:@logger).level)
  end

  def test_start_and_stop
    agent_status = Armagh::AgentStatus.new
    agent_status.config = {}
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    assert_false @agent.running?
    Thread.new { @agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true @agent.running?
    sleep THREAD_SLEEP_TIME
    @agent.stop
    sleep 1
    assert_false @agent.running?
  end

  def test_start_after_failure
    agent_status = Armagh::AgentStatus.new
    agent_status.config = {}
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    client_uri = Armagh::IPC::DRB_CLIENT_URI % @agent.uuid
    socket_file = client_uri.sub("drbunix://",'')

    FileUtils.touch socket_file
    assert_false(File.socket?(socket_file))
    Thread.new { @agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true(File.socket?(socket_file))
  end

  def test_run_with_work
    action_name = 'action_name'
    action = stub(:name => action_name, :execute => nil)
    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta')

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action_from_name).with(action_name).returns(action).at_least_once

    action.expects(:execute).at_least_once
    doc.expects(:remove_pending_action).at_least_once
    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_run_failed_action
    exception = RuntimeError.new
    action_name = 'fail_action'
    action = mock
    action.stubs(:name).returns(action_name)
    action.stubs(:execute).raises(exception)
    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta')

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action_from_name).with(action_name).returns(action).at_least_once

    doc.expects(:remove_pending_action).at_least_once
    doc.expects(:add_failed_action).at_least_once
    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_run_with_work_no_action_exists
    action_name = 'action_name'
    doc = stub(:id => 'document_id', :pending_actions => [action_name])
    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    doc.expects(:add_failed_action).at_least_once
    doc.expects(:remove_pending_action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    Armagh::ActionManager.any_instance.expects(:get_action_from_name).with(action_name).returns(nil).at_least_once

    Armagh::ActionInstance.any_instance.expects(:execute).never
    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, nil).at_least_once

    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_run_no_work
    Armagh::Document.expects(:get_for_processing).returns(nil).at_least_once
    Armagh::ActionInstance.any_instance.expects(:execute).never

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(nil, nil).at_least_once
    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @backoff_mock.expects(:reset).never

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_report_status_no_work
    agent_status = Armagh::AgentStatus.new
    @agent.instance_variable_set(:@agent_status, agent_status)
    @agent.send(:report_status, nil, nil)

    statuses = Armagh::AgentStatus.get_statuses(agent_status)

    assert_includes(statuses, @agent.uuid)
    status = statuses[@agent.uuid]

    assert_equal('idle', status['status'])
    assert_includes(status, 'last_update')
    assert_includes(status, 'idle_since')
  end

  def test_report_status_with_work
    doc = stub(:id => 'document_id')
    action = stub(:name => 'action_id')

    agent_status = Armagh::AgentStatus.new
    @agent.instance_variable_set(:@agent_status, agent_status)
    @agent.send(:report_status, doc, action)

    statuses = Armagh::AgentStatus.get_statuses(agent_status)

    assert_includes(statuses, @agent.uuid)

    status = statuses[@agent.uuid]
    status_task = status['task']

    assert_equal('running', status['status'])
    assert_in_delta(Time.now, status['running_since'], 1)
    assert_in_delta(Time.now, status['last_update'], 1)

    assert_equal(doc.id, status_task['document'])
    assert_equal(action.name, status_task['action'])

    DRb.stop_service
  end

  def test_insert_document
    action = mock
    action.expects(:output_doctype).returns('DocType')
    @agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:create).with('DocType', 'content', 'meta', [], 'id')
    @agent.insert_document('id', 'content', 'meta')
  end

  def test_insert_document_out_of_scope
    logger = @agent.instance_variable_get(:@logger)
    Armagh::Document.expects(:create).never
    logger.expects(:error).with('Document insert can only be called by an action')

    @agent.insert_document(nil, nil, nil)
  end

  def test_update_document
    action = mock
    doc = mock
    action.expects(:output_doctype).returns('DocType')
    @agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:find).with('id').returns doc

    doc.expects(:type=).with('DocType')
    doc.expects(:content=).with('content')
    doc.expects(:meta=).with('meta')
    doc.expects(:add_pending_actions).with([])
    doc.expects(:save)

    @agent.update_document('id', 'content', 'meta')
  end

  def test_update_document_out_of_scope
    logger = @agent.instance_variable_get(:@logger)
    Armagh::Document.expects(:find).never
    logger.expects(:error).with('Document update can only be called by an action')

    @agent.update_document(nil, nil, nil)
  end

  def test_insert_or_update_document_insert
    Armagh::Document.expects(:find).returns(nil)

    action = mock
    action.expects(:output_doctype).returns('DocType')
    @agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:create).with('DocType', 'content', 'meta', [], 'id')
    @agent.insert_or_update_document('id', 'content', 'meta')
  end

  def test_insert_or_update_document_update
    doc = mock
    Armagh::Document.expects(:find).returns(doc)

    action = mock
    action.expects(:output_doctype).returns('DocType')
    @agent.instance_variable_set(:'@current_action', action)

    doc.expects(:type=).with('DocType')
    doc.expects(:content=).with('content')
    doc.expects(:meta=).with('meta')
    doc.expects(:add_pending_actions).with([])
    doc.expects(:save)
    @agent.insert_or_update_document('id', 'content', 'meta')
  end

  def test_insert_or_update_document_out_of_scope
    logger = @agent.instance_variable_get(:@logger)
    Armagh::Document.expects(:find).never
    logger.expects(:error).with('Document insertion or update can only be called by an action')

    @agent.insert_or_update_document(nil, nil, nil)
  end
end