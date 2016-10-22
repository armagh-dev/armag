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

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/agent/agent'
require_relative '../../helpers/mock_logger'
require_relative '../../../lib/agent/agent_status'
require_relative '../../../lib/ipc'
require_relative '../../../lib/document/document'
require_relative '../../../lib/logging'
require_relative '../../../lib/connection'

require 'mocha/test_unit'
require 'test/unit'
require 'log4r'

module Armagh
  module StandardActions
    class CollectTest < Armagh::Actions::Collect
    end
    class SplitTest < Armagh::Actions::Split; end
    class PublishTest < Armagh::Actions::Publish
      define_output_docspec 'docspec', 'This is the output'
    end
    class ConsumeTest < Armagh::Actions::Consume; end
    class DividerTest < Armagh::Actions::Divide; end
    class UnknownAction < Armagh::Actions::Action; end
  end
end

class FakeBlockLogger
  attr_reader :method

  def info
    @method = :info
    yield
  end

  def debug
    @method = :debug
    yield
  end
end

class TestAgent < Test::Unit::TestCase
  include ArmaghTest

  THREAD_SLEEP_TIME = 0.01

  STARTED = []

  def setup

    @logger = mock_logger
    @workflow = mock
    @config_store = []
    @backoff_mock = mock('backoff')
    @current_doc_mock = mock('current_doc')
    @running = true
    @default_agent = prep_an_agent('default', {})
    @state_coll = mock
    Armagh::Connection.stubs(:config).returns(@state_coll)
  end

  def prep_an_agent(config_name, config_values)
    agent_config = Armagh::Agent.create_configuration(@config_store, config_name, config_values)
    agent = Armagh::Agent.new(agent_config, @workflow)
    agent.instance_variable_set(:@backoff, @backoff_mock)
    agent.instance_variable_set(:@current_doc, @current_doc_mock)
    agent.instance_variable_set(:@running, @running)
    agent
  end

  def teardown
    @default_agent.stop if @default_agent
  end

  def setup_action(action_class, config_values={})
    config = action_class.create_configuration(@config_store, action_class.name[/::(.*?)$/, 1].downcase, config_values)
    action_class.new(@default_agent, @logger, config, nil)
  end

  def test_stop
    @default_agent.instance_variable_set(:@running, true)
    assert_true @default_agent.running?
    @default_agent.stop
    assert_false @default_agent.running?
  end

  def test_start
    @default_agent.instance_variable_set(:@running, false)
    assert_false @default_agent.running?

    agent_status = Armagh::AgentStatus.new
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    Thread.new { @default_agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true @default_agent.running?
  end

  def test_valid_config
    config = Armagh::Agent.create_configuration(@config_store, 'good', {
      'agent' => {'log_level' => 'debug'}
    })
    assert_equal 'debug', config.agent.log_level
  end

  def test_invalid_config
    e = assert_raises(Configh::ConfigInitError) {
      Armagh::Agent.create_configuration(@config_store, 'bad', {
        'agent' => {'log_level' => 'justbelowthesurface'}
      })
    }
    assert_equal "Unable to create configuration Armagh::Agent bad: Log level must be one of all, debug, info, warn, dev_warn, ops_warn, error, dev_error, ops_error, fatal, any, off", e.message
  end

  def test_start_with_config
    @logger.expects(:level=).with(Log4r::ERROR).at_least_once
    agent = prep_an_agent('logserror', {'agent' => {'log_level' => 'error'}})

    agent_status = mock

    DRbObject.stubs(:new_with_uri).returns(agent_status)

    Thread.new { agent.start }
    sleep THREAD_SLEEP_TIME
    agent.stop
  end

  def test_start_without_config
    agent_status = mock

    DRbObject.stubs(:new_with_uri).returns(agent_status)

    Thread.new { @default_agent.start }
    sleep THREAD_SLEEP_TIME
  end

  def test_start_and_stop
    @default_agent.instance_variable_set(:@running, false)
    agent_status = Armagh::AgentStatus.new
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    assert_false @default_agent.running?
    Thread.new { @default_agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true @default_agent.running?
    sleep THREAD_SLEEP_TIME
    @default_agent.stop
    sleep 1
    assert_false @default_agent.running?
  end

  def test_start_after_failure
    agent_status = Armagh::AgentStatus.new
    DRbObject.stubs(:new_with_uri).returns(agent_status)

    client_uri = Armagh::IPC::DRB_CLIENT_URI % @default_agent.uuid
    socket_file = client_uri.sub("drbunix://", '')

    FileUtils.touch socket_file
    assert_false(File.socket?(socket_file))
    Thread.new { @default_agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true(File.socket?(socket_file))
  end

  def test_run_collect_action
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect).with()

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => 'content', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once

    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:finish_processing).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_collect_action_collection_history
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    class << action
      define_method(:collect, proc {@caller.instance_variable_set(:@num_creates, 3)})
    end

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => 'content', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once

    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:finish_processing).at_least_once
    doc.expects(:mark_collection_history)
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_collect_action_archive
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:within_archive_context).yields

    Armagh::Actions::Collect.stubs(:report_validation_errors)

    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => true},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })

    action_name = action.config.action.name

    action.expects(:collect).with()

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => 'content', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once

    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:finish_processing).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_split_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    action = setup_action(Armagh::StandardActions::SplitTest, {'input' => {'docspec' => input_docspec}})
    action_name = action.config.action.name

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: {'content' => 'old'}, metadata: {'meta' => 'old'},
                                                       docspec: input_docspec, source: {})
    action.expects(:split).with(action_doc)

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [])
    doc.expects(:to_action_document).returns(action_doc)
    doc.expects(:mark_delete)
    doc.expects(:finish_processing).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_publish_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
      'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: {'old' => 'content'}, metadata: {'old' => 'meta'},
                                                       docspec: input_docspec, source: {})
    action.expects(:publish).with(action_doc)

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false, :collection_task_ids => [], :source => Armagh::Documents::Source.new)
    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once
    @workflow.expects(:get_action_names_for_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:finish_processing).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:get_published_copy).returns(nil)
    doc.expects(:published_timestamp=)
    doc.expects(:display=)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_publish_action_update
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
      'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: {'old' => 'content'}, metadata: {'old' => 'meta'},
                                                       docspec: input_docspec, source: {})
    action.expects(:publish).with(action_doc)

    doc = stub(:document_id => 'document_id',
               :pending_actions => [action_name],
               :content => {'content' => true},
               :metadata => {'meta' => true},
               :type => 'DocumentType',
               :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false,
               :collection_task_ids => [],
               :title => 'old_title',
               :copyright => 'old copyright',
               :display => 'old_display',
               :source => 'old_source',
               :archive_file => 'archive_file')

    pub_doc = stub(:document_id => 'document_id',
                   :pending_actions => [],
                   :type => 'DocumentType',
                   :state => Armagh::Documents::DocState::PUBLISHED,
                   :deleted? => false,
                   :collection_task_ids => [],
                   :content => {'pub_cont': true},
                   :metadata => {'pub_meta' => true},
                   :created_timestamp => 'created',
                   :dev_errors => {},
                   :ops_errors => {},
                   :source => Armagh::Documents::Source.new,
                   :title => 'new title',
                   :internal_id => 'internal',
                   :display => 'new_display',
                   :archive_file => 'new_archive_file')


    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once
    @workflow.expects(:get_action_names_for_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:finish_processing).at_least_once
    doc.expects(:dev_errors).returns({}).at_least_once
    doc.expects(:ops_errors).returns({}).at_least_once
    doc.expects(:get_published_copy).returns(pub_doc)
    doc.expects(:published_timestamp=)
    doc.expects(:display=).with(action_doc.display)

    doc.expects(:created_timestamp=).with(pub_doc.created_timestamp)

    doc.expects(:collection_task_ids).returns []
    doc.expects('published_id=').with(pub_doc.internal_id)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_consume_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    action = setup_action(Armagh::StandardActions::ConsumeTest, {'input' => {'docspec' => input_docspec}})
    action_name = action.config.action.name

    published_doc = Armagh::Documents::PublishedDocument.new(document_id: 'id', content: {'content' => 'old'}, metadata: {'meta' => 'old'},
                                                             docspec: input_docspec, source: {})
    action.expects(:consume).with(published_doc)

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [])
    doc.expects(:to_published_document).returns(published_doc)
    doc.expects(:finish_processing).at_least_once

    doc.expects(:metadata=).with published_doc.metadata

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_divider

    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    divider = setup_action(Armagh::StandardActions::DividerTest, {'input' => {'docspec' => input_docspec}})
    action_name = divider.config.action.name

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true}, :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(divider).at_least_once

    @default_agent.expects(:report_status).with(doc, divider).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_action_with_dev_errors
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect).with()

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => 'content', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:dev_errors).returns({action_name => ['BROKEN']})
    doc.expects(:ops_errors).returns({})

    doc.expects(:finish_processing).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @logger.expects(:dev_error)
    @logger.expects(:ops_error).never

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_action_with_ops_errors
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect).with()

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => 'content', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:ops_errors).returns({'action_name' => ['BROKEN']})
    doc.expects(:dev_errors).returns({})

    doc.expects(:finish_processing).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @logger.expects(:dev_error).never
    @logger.expects(:ops_error)

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_failed_action
    exception = RuntimeError.new
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name
    action.stubs(:collect).raises(exception)

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true}, :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :deleted? => false)

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:add_dev_error)
    doc.expects(:finish_processing).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Armagh::Logging.expects(:dev_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal "Error while executing action '#{action_name}'", msg
      true
    end

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
    @default_agent.stop
  end

  def test_run_with_work_no_action_exists
    action_name = 'action_name'
    doc = stub(:document_id => 'document_id', :pending_actions => [action_name])
    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    doc.expects(:add_ops_error).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(nil).at_least_once

    @default_agent.expects(:report_status).with(doc, nil).at_least_once

    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
    @default_agent.stop
  end

  def test_run_no_work
    Armagh::Document.expects(:get_for_processing).returns(nil).at_least_once

    @default_agent.expects(:report_status).with(nil, nil).at_least_once
    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @backoff_mock.expects(:reset).never

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
    @default_agent.stop
  end

  def test_run_not_action
    action = 'Not an action'
    action_name = 'action_name'

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [])

    doc.expects(:finish_processing).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once

    @logger.expects(:dev_error).with("#{action} is not an action.")

    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Thread.new { @default_agent.send(:run) }
    sleep THREAD_SLEEP_TIME
  end

  def test_run_unexpected_error
    exception = RuntimeError.new 'Exception'
    Armagh::Document.expects(:get_for_processing).raises(exception)

    Armagh::Logging.expects(:dev_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal 'An unexpected error occurred', msg
      true
    end

    @default_agent.instance_variable_set(:@running, true)
    @default_agent.send(:run)
  end

  def test_report_status_no_work
    agent_status = Armagh::AgentStatus.new
    @default_agent.instance_variable_set(:@agent_status, agent_status)
    @default_agent.send(:report_status, nil, nil)

    statuses = Armagh::AgentStatus.get_statuses(agent_status)

    assert_includes(statuses, @default_agent.uuid)
    status = statuses[@default_agent.uuid]

    assert_equal('idle', status['status'])
    assert_includes(status, 'last_update')
    assert_includes(status, 'idle_since')
  end

  def test_report_status_with_work
    doc = stub(:document_id => 'document_id')
    action = stub(:name => 'action_id')

    agent_status = Armagh::AgentStatus.new
    @default_agent.instance_variable_set(:@agent_status, agent_status)
    @default_agent.send(:report_status, doc, action)

    statuses = Armagh::AgentStatus.get_statuses(agent_status)

    assert_includes(statuses, @default_agent.uuid)

    status = statuses[@default_agent.uuid]
    status_task = status['task']

    assert_equal('running', status['status'])
    assert_in_delta(Time.now, status['running_since'], 1)
    assert_in_delta(Time.now, status['last_update'], 1)

    assert_equal(doc.document_id, status_task['document'])
    assert_equal(action.name, status_task['action'])

    DRb.stop_service
  end

  def test_instantiate_divider
    docspec = Armagh::Documents::DocSpec.new('type', Armagh::Documents::DocState::READY)
    @workflow.expects(:instantiate_divider).with(docspec, @default_agent, @logger, @state_coll)
    @default_agent.instantiate_divider(docspec)
  end

  def test_create_document
    action = mock
    @current_doc_mock.expects(:document_id).returns('current_id')
    @workflow.expects(:get_action_names_for_docspec).returns([]).at_least_once

    @default_agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:create).with(type: 'DocumentType',
                                           content: 'content',
                                           metadata: 'metadata',
                                           pending_actions: [],
                                           state: Armagh::Documents::DocState::WORKING,
                                           document_id: 'id',
                                           new: true,
                                           collection_task_ids: [],
                                           document_timestamp: nil,
                                           source: {'some' => 'source'},
                                           title: nil,
                                           copyright: nil,
                                           logger: @logger,
                                           archive_file: nil,
                                           display: nil)
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: 'content',
                                                       metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING),
                                                       source: {'some' => 'source'})
    @default_agent.create_document action_doc
  end

  def test_create_document_current
    id = 'id'
    @current_doc_mock.expects(:document_id).returns(id)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: id, content: 'content', metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING), source: {})

    e = assert_raise(Armagh::Documents::Errors::DocumentError) do
      @default_agent.create_document action_doc
    end

    assert_equal("Cannot create document 'id'.  It is the same document that was passed into the action.", e.message)
  end

  def test_edit_document
    doc = mock('document')
    doc.expects(:is_a?).with(Armagh::Document).returns(true)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    @workflow.expects(:get_action_names_for_docspec).returns([]).at_least_once

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    new_content = {'new content' => true}
    new_meta = {'new meta' => true}
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)

    doc.expects(:clear_pending_actions)
    doc.expects(:add_pending_actions).with([])
    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id, content: {'content' => true},
                                                                                   metadata: {'meta' => true},
                                                                                   docspec: old_docspec,
                                                                                   source: {}))

    doc.expects(:update_from_draft_action_document).with do |action_doc|
      assert_equal(new_content, action_doc.content)
      assert_equal(new_meta, action_doc.metadata)
      assert_equal(new_docspec, action_doc.docspec)
      true
    end
    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(doc)

    executed_block = false
    @default_agent.edit_document(id, old_docspec) do |doc|
      assert_equal(Armagh::Documents::ActionDocument, doc.class)
      assert_false doc.new_document?
      doc.metadata = new_meta
      doc.content = new_content
      doc.docspec = new_docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_current
    id = 'id'
    @current_doc_mock.expects(:document_id).returns(id)

    e = assert_raise(Armagh::Documents::Errors::DocumentError) do
      @default_agent.edit_document(id, Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY))
    end

    assert_equal("Cannot edit document 'id'.  It is the same document that was passed into the action.", e.message)
  end

  def test_edit_document_no_block
    @current_doc_mock.expects(:document_id).returns('current_id')
    logger = @default_agent.instance_variable_get(:@logger)
    logger.expects(:dev_warn).with("edit_document called for document '123' but no block was given.  Ignoring.")
    @default_agent.edit_document(123, Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY))
  end

  def test_edit_document_new
    doc = mock('document')
    @current_doc_mock.expects(:document_id).returns('current_id')
    doc.expects(:internal_id=)

    @workflow.expects(:get_action_names_for_docspec).returns([]).at_least_once

    id = 'id'
    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    content = {'new content' => true}
    meta = {'new meta' => true}

    doc.expects(:save).returns nil

    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state, @running, @logger).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    executed_block = false
    @default_agent.edit_document(id, docspec) do |doc|
      assert_equal(Armagh::Documents::ActionDocument, doc.class)
      assert_true doc.new_document?
      doc.metadata = meta
      doc.content = content
      doc.docspec = docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_change_type
    doc = mock('document')
    doc.expects(:is_a?).with(Armagh::Document).returns(true)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('ChangedType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id, content: 'old content',
                                                                                   metadata: 'old meta',
                                                                                   docspec: old_docspec, source: {}))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(doc)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_same_state
    doc = mock('document')
    doc.expects(:is_a?).with(Armagh::Document).returns(true)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id, content: 'old content',
                                                                                   metadata: 'old meta',
                                                                                   docspec: docspec, source: {}))

    doc.expects(:update_from_draft_action_document).with do |action_doc|
      assert_equal(docspec, action_doc.docspec)
      true
    end
    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state, @running, @logger).yields(doc)

    @default_agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_change_state_w_p
    doc = mock('document')
    doc.expects(:is_a?).with(Armagh::Document).returns(true)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id, content: 'old content',
                                                                                   metadata: 'old meta',
                                                                                   docspec: old_docspec, source: {}))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(doc)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_change_state_r_w
    doc = mock('document')
    doc.expects(:is_a?).with(Armagh::Document).returns(true)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id, content: 'content',
                                                                                   metadata: 'meta', docspec: old_docspec, source: {}))

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(doc)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_change_type
    id = 'id'
    @current_doc_mock.expects(:document_id).returns('current_id')

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('ChangedType', Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(nil)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_new_same_state
    doc = mock('document')
    doc.expects(:internal_id=)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    @workflow.expects(:get_action_names_for_docspec).returns([]).at_least_once
    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    doc.expects(:save).returns

    Armagh::Document.expects(:modify_or_create).with(id, docspec.type, docspec.state, @running, @logger).yields(nil)
    Armagh::Document.expects(:from_action_document).returns doc

    @default_agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_new_change_state_w_p
    id = 'id'
    @current_doc_mock.expects(:document_id).returns('current_id')

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(nil)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_new_change_state_r_w
    id = 'id'
    @current_doc_mock.expects(:document_id).returns('current_id')

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:modify_or_create).with(id, old_docspec.type, old_docspec.state, @running, @logger).yields(nil)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_get_existing_published_document
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: {'content' => true}, metadata: {'meta' => true},
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY),
                                                       source: {})
    doc = mock('db doc')
    pub_action_doc = mock
    doc.expects(:to_published_document).returns(pub_action_doc)

    Armagh::Document.expects(:find).returns(doc)
    assert_equal(pub_action_doc, @default_agent.get_existing_published_document(action_doc))
  end

  def test_get_existing_published_document_none
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: {'content' => true}, metadata: {'meta' => true},
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY),
                                                       source: {})
    Armagh::Document.expects(:find).returns(nil)
    assert_nil @default_agent.get_existing_published_document(action_doc)
  end

  def test_log_debug
    message = 'test message'
    logger_name = 'test_logger'
    logger = mock('logger')
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    logger.expects(:debug).with(message)
    @default_agent.log_debug(logger_name, message)
  end

  def test_log_debug_block
    logger_name = 'test_logger'
    logger = FakeBlockLogger.new
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger).yields(nil)
    block_called = false
    @default_agent.log_debug(logger_name) { block_called = true }
    assert_true block_called
    assert_equal(:debug, logger.method)
  end

  def test_log_info
    message = 'test message'
    logger_name = 'test_logger'
    logger = mock('logger')
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    logger.expects(:info).with(message)
    @default_agent.log_info(logger_name, message)
  end

  def test_log_info_block
    logger_name = 'test_logger'
    logger = FakeBlockLogger.new
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger).yields(nil)
    block_called = false
    @default_agent.log_info(logger_name) { block_called = true }
    assert_true block_called
    assert_equal(:info, logger.method)
  end

  def test_notify_ops
    logger_name = 'logger'
    action_name = 'action'
    message = 'message'
    logger = mock
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    @current_doc_mock.expects(:add_ops_error).with(action_name, message)
    logger.expects(:ops_error).with(message)
    @default_agent.notify_ops(logger_name, action_name, message)
  end

  def test_notify_dev
    logger_name = 'logger'
    action_name = 'action'
    message = 'message'
    logger = mock
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    @current_doc_mock.expects(:add_dev_error).with(action_name, message)
    logger.expects(:dev_error).with(message)
    @default_agent.notify_dev(logger_name, action_name, message)
  end

  def test_notify_ops_exception
    logger_name = 'logger'
    action_name = 'action'
    error = RuntimeError.new('error')
    logger = mock
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    @current_doc_mock.expects(:add_ops_error).with(action_name, error)
    Armagh::Logging.expects(:ops_error_exception).with(logger, error, 'Notify Ops')
    @default_agent.notify_ops(logger_name, action_name, error)
  end

  def test_notify_dev_exception
    logger_name = 'logger'
    action_name = 'action'
    error = RuntimeError.new('error')
    logger = mock
    Log4r::Logger.expects(:[]).with(logger_name).returns(logger)
    @current_doc_mock.expects(:add_dev_error).with(action_name, error)
    Armagh::Logging.expects(:dev_error_exception).with(logger, error, 'Notify Dev')
    @default_agent.notify_dev(logger_name, action_name, error)
  end

  def test_get_logger
    logger_name = 'test_logger'
    logger = mock('logger')
    Armagh::Logging.expects(:set_logger).with(logger_name).returns(logger)
    assert_equal logger, @default_agent.get_logger(logger_name)
  end

  def test_archive
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    metadata = {}
    source = Armagh::Documents::Source.new
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, metadata, source)

    @default_agent.archive(logger_name, action_name, file_path, metadata, source)
  end

  def test_archive_archive_error
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    metadata = {}
    source = Armagh::Documents::Source.new
    error = Armagh::Errors::ArchiveError.new('archive_error')
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, metadata, source).raises(error)
    @default_agent.expects(:notify_dev).with(logger_name, action_name, error)

    @default_agent.archive(logger_name, action_name, file_path, metadata, source)
  end

  def test_archive_sftp_error
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    metadata = {}
    source = Armagh::Documents::Source.new
    error = Armagh::Support::SFTP::SFTPError.new('sftp error')
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, metadata, source).raises(error)
    @default_agent.expects(:notify_ops).with(logger_name, action_name, error)

    @default_agent.archive(logger_name, action_name, file_path, metadata, source)
  end

  def test_too_large
    exception = Armagh::Documents::Errors::DocumentSizeError.new('too large')
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'collected_doc' => 'dancollected:ready'}
    })
    action_name = action.config.action.name
    action.stubs(:collect).raises(exception)

    doc = stub(:document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :deleted? => false,
               :dev_errors => [], :ops_errors => [], :eggs => 'wee'
    )

    Armagh::Document.expects(:get_for_processing).returns(doc).at_least_once
    @workflow.expects(:instantiate_action).with(action_name, @default_agent, @logger, @state_coll).returns(action).at_least_once

    doc.expects(:add_ops_error)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    doc.expects(:finish_processing).at_least_once

    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Armagh::Logging.expects(:ops_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal "Error while executing action '#{action_name}'", msg
      true
    end

    @default_agent.expects(:execute_action).raises(exception)
    @default_agent.send(:execute)
  end

end
