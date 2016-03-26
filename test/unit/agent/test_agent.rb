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

require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/agent/agent'
require_relative '../test_helpers/mock_global_logger'
require_relative '../../../lib/agent/agent_status'
require_relative '../../../lib/ipc'
require_relative '../../../lib/document/document'
require_relative '../../../lib/action/action_manager'

require 'mocha/test_unit'
require 'test/unit'
require 'logger'

class CollectTest < Armagh::CollectAction; end
class ParseTest < Armagh::ParseAction; end
class PublishTest < Armagh::PublishAction; end
class ConsumeTest < Armagh::ConsumeAction; end
class SplitterTest < Armagh::CollectionSplitter; end
class UnknownAction < Armagh::Action; end

class TestAgent < Test::Unit::TestCase
  include ArmaghTest

  THREAD_SLEEP_TIME = 0.01

  STARTED = []

  def setup
    @logger = mock_global_logger
    @logger.expects(:debug).at_least(0)
    @logger.expects(:info).at_least(0)
    @logger.expects(:warn).at_least(0)
    @logger.expects(:error).at_least(0)
    @logger.expects(:unknown).at_least(0)
    @logger.expects(:level).at_least(0)

    @agent = Armagh::Agent.new
    @backoff_mock = mock('object')
    @agent.instance_variable_set(:@backoff, @backoff_mock)
  end

  def teardown
    @agent.stop
  end

  def setup_action(action_class)
    action_class.new(action_class.to_s, @agent, @logger, {}, {})
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
    @logger.expects(:level=).with(Logger::ERROR).at_least_once

    agent_status = mock
    agent_status.stubs(:config).returns(config)

    DRbObject.stubs(:new_with_uri).returns(agent_status)

    Thread.new { @agent.start }
    sleep THREAD_SLEEP_TIME
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

  def test_run_collect_action
    action_name = 'action_name'
    action = setup_action(CollectTest)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
    action.expects(:collect).with()

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once

    doc.expects(:finish_processing).never
    doc.expects(:delete)

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_parse_action
    action_name = 'action_name'
    action = setup_action(ParseTest)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
    action.expects(:parse).with(action_doc)

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :deleted? => true)
    doc.expects(:to_action_document).returns(action_doc)
    doc.expects(:delete)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_publish_action
    action_name = 'action_name'
    action = setup_action(PublishTest)
    pending_actions = %w(one two)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
    action.expects(:publish).with(action_doc)

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING, :deleted? => false)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action_names_for_docspec).returns(pending_actions)

    doc.expects(:meta=, action_doc.meta)
    doc.expects(:published_content=, action_doc.draft_content)
    doc.expects(:draft_content=, {})
    doc.expects(:state=, Armagh::DocState::PUBLISHED)
    doc.expects(:add_pending_actions).with(pending_actions)
    doc.expects(:delete).never

    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_consume_action
    action_name = 'action_name'
    action = setup_action(ConsumeTest)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
    action.expects(:consume).with(action_doc)

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING, :deleted? => false)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once

    doc.expects(:meta=, action_doc.meta)
    doc.expects(:draft_content=, action_doc.draft_content)
    doc.expects(:delete).never

    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_splitter
    action_name = 'action_name'
    splitter = SplitterTest.new(@agent, @logger, {}, {})

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(splitter).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, splitter).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)
    @logger.expects(:error).with("#{splitter} is an not an action.")

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_invalid_action
    action_name = 'action_name'
    action = setup_action(UnknownAction)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING, :deleted? => false)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once

    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)
    @logger.expects(:error).with("#{action.name} is an unknown action type.")

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
  end

  def test_run_failed_action
    exception = RuntimeError.new
    action_name = 'fail_action'
    action = setup_action(CollectTest)
    action.stubs(:collect).raises(exception)

    action_doc = Armagh::ActionDocument.new('id', 'old content', 'published content', 'old meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))

    doc = stub(:id => 'document_id', :pending_actions => [action_name], :content => 'content', :meta => 'meta', :type => 'DocumentType', :state => Armagh::DocState::WORKING, :deleted? => false)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(action).at_least_once

    doc.expects(:add_failed_action)
    doc.expects(:finish_processing).at_least_once

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @agent.instance_variable_set(:@running, true)
    @logger.expects(:error).with("Error while executing action '#{action_name}'")

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_run_with_work_no_action_exists
    action_name = 'action_name'
    doc = stub(:id => 'document_id', :pending_actions => [action_name])
    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    doc.expects(:add_failed_action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    Armagh::ActionManager.any_instance.expects(:get_action).with(action_name).returns(nil).at_least_once

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

    @agent.expects(:update_config).at_least_once
    @agent.expects(:report_status).with(nil, nil).at_least_once
    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @backoff_mock.expects(:reset).never

    @agent.instance_variable_set(:@running, true)

    Thread.new {@agent.send(:run)}
    sleep THREAD_SLEEP_TIME
    @agent.stop
  end

  def test_run_unexpected_error
    exception = RuntimeError, 'Exception'
    @agent.expects(:update_config).raises(exception)
    @logger.expects(:error).with('An unexpected error occurred.')

    @agent.instance_variable_set(:@running, true)
    @agent.send(:run)
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

  def test_create_document
    action = mock
    @agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:create).with('DocumentType', 'draft_content', 'published_content', 'meta', [], Armagh::DocState::WORKING, 'id', true)
    action_doc = Armagh::ActionDocument.new('id', 'draft_content', 'published_content', 'meta', Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING))
    @agent.create_document action_doc
  end

  def test_edit_document
    doc = mock('document')

    id = 'id'
    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    new_content = 'new content'
    new_meta = 'new meta'
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)

    doc.expects(:clear_pending_actions)
    doc.expects(:add_pending_actions).with([])
    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    doc.expects(:update_from_action_document).with do |action_doc|
      assert_equal(new_content, action_doc.draft_content)
      assert_equal(new_meta, action_doc.meta)
      assert_equal(new_docspec, action_doc.docspec)
      assert_equal('published content', action_doc.published_content)
      true
    end
    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(doc)

    executed_block = false
    @agent.edit_document(id, old_docspec) do |doc|
      assert_equal(Armagh::ActionDocument, doc.class)
      assert_false doc.new_document?
      doc.meta = new_meta
      doc.draft_content = new_content
      doc.docspec = new_docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_no_block
    logger = @agent.instance_variable_get(:@logger)
    logger.expects(:warn).with("edit_document called for document '123' but no block was given.  Ignoring.")
    @agent.edit_document(123, Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
  end

  def test_edit_document_new
    doc = mock('document')

    id = 'id'
    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    content = 'new content'
    meta = 'new meta'

    doc.expects(:finish_processing).returns nil

    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    executed_block = false
    @agent.edit_document(id, docspec) do |doc|
      assert_equal(Armagh::ActionDocument, doc.class)
      assert_true doc.new_document?
      doc.meta = meta
      doc.draft_content = content
      doc.docspec = docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_change_type
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('ChangedType', Armagh::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(doc)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_same_state
    doc = mock('document')
    id = 'id'

    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', docspec))

    doc.expects(:update_from_action_document).with do |action_doc|
      assert_equal(docspec, action_doc.docspec)
      true
    end
    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state).yields(doc)

    @agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_change_state_w_p
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::PUBLISHED)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(doc)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_change_state_r_w
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(doc)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_change_type
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('ChangedType', Armagh::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_new_same_state
    doc = mock('document')
    id = 'id'

    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    doc.expects(:finish_processing).returns nil

    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    @agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_new_change_state_w_p
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::PUBLISHED)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_change_state_r_w
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_bang
    doc = mock('document')

    id = 'id'
    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    new_content = 'new content'
    new_meta = 'new meta'
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)

    doc.expects(:clear_pending_actions)
    doc.expects(:add_pending_actions).with([])
    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    doc.expects(:update_from_action_document).with do |action_doc|
      assert_equal(new_content, action_doc.draft_content)
      assert_equal(new_meta, action_doc.meta)
      assert_equal(new_docspec, action_doc.docspec)
      assert_equal('published content', action_doc.published_content)
      true
    end
    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(doc).returns(true)

    executed_block = false
    result = @agent.edit_document!(id, old_docspec) do |doc|
      assert_equal(Armagh::ActionDocument, doc.class)
      assert_false doc.new_document?
      doc.meta = new_meta
      doc.draft_content = new_content
      doc.docspec = new_docspec
      executed_block = true
    end

    assert_true result
    assert_true executed_block
  end

  def test_edit_document_bang_no_block
    logger = @agent.instance_variable_get(:@logger)
    logger.expects(:warn).with("edit_document! called for document '123' but no block was given.  Ignoring.")
    @agent.edit_document!(123, Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY))
  end

  def test_edit_document_new_bang
    doc = mock('document')

    id = 'id'
    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    content = 'new content'
    meta = 'new meta'

    doc.expects(:finish_processing).returns nil

    Armagh::Document.expects(:modify_or_create!).with(id, docspec.type, docspec.state).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    executed_block = false
    @agent.edit_document!(id, docspec) do |doc|
      assert_equal(Armagh::ActionDocument, doc.class)
      assert_true doc.new_document?
      doc.meta = meta
      doc.draft_content = content
      doc.docspec = docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_bang_change_type
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('ChangedType', Armagh::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(doc).returns(true)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_bang_same_state
    doc = mock('document')
    id = 'id'

    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create!).with(id, docspec.type, docspec.state).yields(doc).returns(true)
    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', docspec))

    doc.expects(:update_from_action_document).with do |action_doc|
      assert_equal(docspec, action_doc.docspec)
      true
    end

    @agent.edit_document!(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_bang_change_state_r_w
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(doc).returns(true)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_bang_change_state_w_p
    doc = mock('document')
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::PUBLISHED)

    doc.expects(:to_action_document).returns(Armagh::ActionDocument.new(id, 'old content', 'published content', 'old meta', old_docspec))

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(doc).returns(true)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_bang_change_type
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('ChangedType', Armagh::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_new_bang_same_state
    doc = mock('document')
    id = 'id'

    docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    doc.expects(:finish_processing).returns nil

    Armagh::Document.expects(:modify_or_create!).with(id, docspec.type, docspec.state).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    @agent.edit_document!(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_new_bang_change_state_w_p
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::PUBLISHED)

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_bang_change_state_r_w
    id = 'id'

    old_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::READY)
    new_docspec = Armagh::DocSpec.new('DocumentType', Armagh::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create!).with(id, old_docspec.type, old_docspec.state).yields(nil)

    e = assert_raise(Armagh::ActionErrors::DocSpecError) do
      @agent.edit_document!(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_get_splitter
    splitter = SplitterTest.new(@agent, @logger, {}, {})
    Armagh::ActionManager.any_instance.expects(:get_splitter).returns(splitter)
    assert_equal(splitter, @agent.get_splitter('invalid', 'invalid'))
  end

  def test_get_splitter_none
    Armagh::ActionManager.any_instance.expects(:get_splitter).returns(nil)
    assert_nil @agent.get_splitter('invalid', 'invalid')
  end
end
