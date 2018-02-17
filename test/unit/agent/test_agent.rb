# Copyright 2018 Noragh Analytics, Inc.
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
require_relative '../../helpers/armagh_test/logger'

require_relative '../../../lib/armagh/agent/agent'
require_relative '../../../lib/armagh/document/document'
require_relative '../../../lib/armagh/document/action_state_document'
require_relative '../../../lib/armagh/connection'

require 'armagh/logging'

require 'fileutils'

require 'mocha/test_unit'
require 'test/unit'

module Armagh
  module StandardActions
    class CollectTest < Armagh::Actions::Collect
      define_output_docspec 'output_type', 'action description', default_type: 'OutputDocument', default_state: Armagh::Documents::DocState::READY
    end
    class SplitTest < Armagh::Actions::Split
      define_output_docspec 'output_type', 'action description', default_type: 'OutputDocument', default_state: Armagh::Documents::DocState::READY
    end
    class PublishTest < Armagh::Actions::Publish; end
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

  THREAD_SLEEP_TIME = 0.75

  def setup
    @logger = mock_logger
    @workflow_set = mock('workflow set')
    @hostname = 'test-hostname'
    @config_store = []
    @backoff_mock = mock('backoff')
    @current_doc_mock = mock('current_doc')
    @current_doc_mock.stubs( document_id:'current_id' )
    @running = true
    @agent_id = 'agent_id'
    @archive_config_values = {
      'sftp' => {
        'username' => 'testuser',
        'host' => 'localhost',
        'directory_path' => '/tmp/var/archive'
      }
    }
    @default_agent = prep_an_agent('default', 'archive_config_name',{}, @agent_id)
    @state_coll = mock
    @temp_dir = '/tmp/armagh_agent_test'
    FileUtils.mkdir_p @temp_dir
    Armagh::Connection.stubs(:action_state).returns(@state_coll)

    Thread.abort_on_exception = true
  end

  def prep_an_agent(config_name, archive_config_name, config_values, id)
    Armagh::Support::SFTP.stubs(:test_connection)
    agent_config = Armagh::Agent.create_configuration(@config_store, config_name, config_values)
    archive_config = Armagh::Utils::Archiver.create_configuration(@config_store, archive_config_name, @archive_config_values)
    agent = Armagh::Agent.new(agent_config, archive_config,@workflow_set, @hostname)
    agent.instance_variable_set(:@backoff, @backoff_mock)
    agent.instance_variable_set(:@current_doc, @current_doc_mock)
    agent.instance_variable_set(:@running, @running)
    agent
  end

  def prep_working_doc( new_document: false)
    doc = mock('document')
    doc.stubs( internal_id: 'internal_id', document_id: 'id', new_document?: new_document )
    doc
  end

  def set_expectations_on_new_doc( doc, type: nil, state: nil, pending_actions: [], content: nil, raw: nil, metadata: nil, expect_update_from_action_document: true )
    docspec = Armagh::Documents::DocSpec.new( type, state )
    @workflow_set.expects(:actions_names_handling_docspec).returns([]).at_least_once

    doc.expects( :document_id= ).with( doc.document_id)
    doc.expects( :type= ).with( type )
    doc.expects( :state= ).with( state )
    doc.expects( :pending_actions= ).with(pending_actions)
    doc.expects( :to_action_document ).returns(Armagh::Documents::ActionDocument.new(document_id: doc.document_id,
                                                                                     content: content,
                                                                                     raw: raw,
                                                                                     title: nil,
                                                                                     metadata: metadata,
                                                                                     docspec: docspec,
                                                                                     source: nil,
                                                                                     copyright: nil,
                                                                                     document_timestamp: nil ))

    Armagh::Document.expects(:with_new_or_existing_locked_document).with(doc.document_id, type, state, @default_agent ).yields(doc)

    if expect_update_from_action_document
      doc.expects(:update_from_draft_action_document).with do |action_doc|
        assert_equal(content, action_doc.content)
        assert_equal(raw, action_doc.raw)
        assert_equal(metadata, action_doc.metadata)
        assert_equal(docspec, action_doc.docspec)
        true
      end
    end
  end

  def teardown
    @default_agent.stop if @default_agent
    FileUtils.rm_rf @temp_dir
  end

  def setup_action(action_class, config_values={})
    config = action_class.create_configuration(@config_store, action_class.name[/::(.*?)$/, 1].downcase, config_values)
    action_class.new(@default_agent, @logger, config)
  end

  def test_stop
    @default_agent.instance_variable_set(:@running, true)
    assert_true @default_agent.running?
    @default_agent.stop
    assert_false @default_agent.running?
  end

  def test_start
    @backoff_mock.stubs(:interruptible_backoff)
    @default_agent.instance_variable_set(:@running, false)
    assert_false @default_agent.running?

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
    assert_equal "Unable to create configuration for 'Armagh::Agent' named 'bad' because: \n    Group 'agent' Parameter 'log_level': value is not one of the options (debug,info,warn,ops_warn,dev_warn,error,ops_error,dev_error,fatal,any)", e.message
  end

  def test_start_with_config
    @backoff_mock.stubs(:interruptible_backoff)
    Armagh::Logging.expects(:set_level).with(@logger, 'error').at_least_once
    agent = prep_an_agent('logserror', 'archive', {'agent' => {'log_level' => 'error'}}, 'start_id')

    Thread.new { agent.start }
    sleep THREAD_SLEEP_TIME
    agent.stop
  end

  def test_start_without_config
    @backoff_mock.stubs(:interruptible_backoff)

    Thread.new { @default_agent.start}

    sleep THREAD_SLEEP_TIME
    assert_true @default_agent.running?
  end

  def test_start_and_stop
    @backoff_mock.stubs(:interruptible_backoff)
    @default_agent.instance_variable_set(:@running, false)

    assert_false @default_agent.running?
    Thread.new { @default_agent.start }
    sleep THREAD_SLEEP_TIME
    assert_true @default_agent.running?
    sleep THREAD_SLEEP_TIME
    @default_agent.stop
    sleep 1
    assert_false @default_agent.running?
  end

  def test_run_collect_action
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => 'content', :raw => 'raw data', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:mark_delete)
    doc.expects(:metadata).returns({})

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_collect_action_collection_history
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    class << action
      define_method(:collect, proc {@caller.instance_variable_set(:@num_creates, 3)})
    end

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => 'content', :raw => 'raw data', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:mark_collection_history)
    doc.expects(:metadata).returns({})

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)
    @default_agent.send(:execute)
  end

  def test_run_collect_action_archive
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:within_archive_context).yields

    Armagh::Actions::Collect.stubs(:report_validation_errors)

    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action'  => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => true},
      'input'   => {'docspec' => '__COLLECT__testc:ready'},
      'output'  => {'docspec' => 'dancollected:ready'}
    })

    action_name = action.config.action.name

    action.expects(:collect).with()

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => 'content', :raw => 'raw data', :metadata => 'meta', :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:mark_delete)
    doc.expects(:metadata).returns({})

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_split_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('OutputDocumentType', Armagh::Documents::DocState::READY)
    action = setup_action(Armagh::StandardActions::SplitTest, {
        'action' => { 'workflow' => 'wf' },
        'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'content' => 'old'},
                                                       raw: 'old',
                                                       metadata: {'meta' => 'old'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)
    action.expects(:split).with(action_doc)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true},
               :raw => 'new', :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [],
               :archive_files => [], :error => nil)
    doc.expects(:to_action_document).returns(action_doc)
    doc.expects(:mark_delete)
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
        'action' => { 'workflow' => 'wf' },
        'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = [ 'one', 'two' ]

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: 'Some Title',
                                                       copyright: nil,
                                                       document_timestamp: nil)
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => pending_actions, :content => {'content' => true},
               :raw => 'action', :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false, :collection_task_ids => [], archive_files: [], :source => Armagh::Documents::Source.new,
               :error => nil, title: 'Some Title')
    doc.expects(:to_action_document).returns(action_doc)

    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    @workflow_set.expects(:actions_names_handling_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ])
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_items_to_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:get_published_copy_read_only).returns(nil)
    doc.expects(:published_timestamp=)
    doc.expects(:display=)
    doc.expects(:version=).with(1)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @logger.unstub(:dev_warn)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action_set_version
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
      'action' => { 'workflow' => 'wf' },
      'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = [ 'one', 'two' ]

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil,
                                                       version: 123
    )
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => pending_actions, :content => {'content' => true},
               :raw => 'action', :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false, :collection_task_ids => [], archive_files: [], :source => Armagh::Documents::Source.new,
               :error => nil, :version => 123, title: 'Some Title')
    doc.expects(:to_action_document).returns(action_doc)

    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    @workflow_set.expects(:actions_names_handling_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ])
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_items_to_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:get_published_copy_read_only).returns(nil)
    doc.expects(:published_timestamp=)
    doc.expects(:display=)
    doc.expects(:version=).with(123)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @logger.unstub(:dev_warn)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action_no_title
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
      'action' => { 'workflow' => 'wf' },
      'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = [ 'one', 'two' ]

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => pending_actions, :content => {'content' => true},
               :raw => 'action', :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false, :collection_task_ids => [], archive_files: [], :source => Armagh::Documents::Source.new,
               :error => nil, :title => nil)
    doc.expects(:to_action_document).returns(action_doc)

    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    @workflow_set.expects(:actions_names_handling_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ])
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:title=, "#{doc.document_id} (unknown title)")
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_items_to_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:get_published_copy_read_only).returns(nil)
    doc.expects(:published_timestamp=)
    doc.expects(:display=)
    doc.expects(:version=).with(1)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action_update
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
        'action' => { 'workflow' => 'wf' },
        'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil,
                                                       version: 2
    )
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123',
               :document_id => 'document_id',
               :pending_actions => [],
               :content => {'content' => true},
               :raw => 'action',
               :metadata => {'meta' => true},
               :type => 'DocumentType',
               :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false,
               :collection_task_ids => [],
               :title => 'old_title',
               :copyright => 'old copyright',
               :display => 'old_display',
               :source => 'old_source',
               :archive_files => ['archive_file'],
               :version => 1,
               :error => nil)

    pub_doc = stub(:document_id => 'document_id',
                   :pending_actions => [],
                   :type => 'DocumentType',
                   :state => Armagh::Documents::DocState::PUBLISHED,
                   :deleted? => false,
                   :collection_task_ids => [],
                   :content => {'pub_cont': true},
                   :raw => 'pub',
                   :metadata => {'pub_meta' => true},
                   :created_timestamp => 'created',
                   :dev_errors => {},
                   :ops_errors => {},
                   :source => Armagh::Documents::Source.new,
                   :title => 'old title',
                   :internal_id => 'internal',
                   :display => 'old display',
                   :archive_files => ['old_archive_file'],
                   :version => 1,
                   :document_timestamp => nil
    )

    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    @workflow_set.expects(:actions_names_handling_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ]).with('action')
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_items_to_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:dev_errors).returns({}).at_least_once
    doc.expects(:ops_errors).returns({}).at_least_once
    doc.expects(:get_published_copy_read_only).returns(pub_doc)
    doc.expects(:published_timestamp=)
    doc.expects(:display=).with(action_doc.display)
    doc.expects(:version=).with(2)

    doc.expects(:created_timestamp=).with(pub_doc.created_timestamp)

    doc.expects(:collection_task_ids).returns []
    doc.expects('published_id=').with(pub_doc.internal_id)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @logger.unstub(:dev_warn)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action_update_reduce_version
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
      'action' => { 'workflow' => 'wf' },
      'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil,
                                                       version: 2
    )
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123',
               :document_id => 'document_id',
               :pending_actions => [],
               :content => {'content' => true},
               :raw => 'action',
               :metadata => {'meta' => true},
               :type => 'DocumentType',
               :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false,
               :collection_task_ids => [],
               :title => 'old_title',
               :copyright => 'old copyright',
               :display => 'old_display',
               :source => 'old_source',
               :archive_files => ['archive_file'],
               :version => 10,
               :error => nil)

    pub_doc = stub(:document_id => 'document_id',
                   :pending_actions => [],
                   :type => 'DocumentType',
                   :state => Armagh::Documents::DocState::PUBLISHED,
                   :deleted? => false,
                   :collection_task_ids => [],
                   :content => {'pub_cont': true},
                   :raw => 'pub',
                   :metadata => {'pub_meta' => true},
                   :created_timestamp => 'created',
                   :dev_errors => {},
                   :ops_errors => {},
                   :source => Armagh::Documents::Source.new,
                   :title => 'old title',
                   :internal_id => 'internal',
                   :display => 'old display',
                   :archive_files => ['old_archive_file'],
                   :version => 10,
                   :document_timestamp => nil
    )

    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    @workflow_set.expects(:actions_names_handling_docspec).returns(pending_actions)

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ]).with('action')
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED)
    doc.expects(:document_timestamp=)
    doc.expects(:add_items_to_pending_actions).with(pending_actions)
    doc.expects(:delete).never
    doc.expects(:mark_publish).at_least_once
    doc.expects(:dev_errors).returns({}).at_least_once
    doc.expects(:ops_errors).returns({}).at_least_once
    doc.expects(:get_published_copy_read_only).returns(pub_doc)
    doc.expects(:published_timestamp=)
    doc.expects(:display=).with(action_doc.display)
    doc.expects(:version=).with(2)

    doc.expects(:created_timestamp=).with(pub_doc.created_timestamp)

    doc.expects(:collection_task_ids).returns []
    doc.expects('published_id=').with(pub_doc.internal_id)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @logger.unstub(:dev_warn)
    @logger.expects(:dev_warn).with("Action #{action.name} changed a previously published version of #{doc.type} #{doc.document_id} from version 10 to a lower value of 2.")

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_publish_action_update_with_older_document
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
        'action' => { 'workflow' => 'wf' },
        'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil,
                                                       version: 2
    )
    action.expects(:publish).with(action_doc)

    doc = stub(:internal_id => '123',
               :document_id => 'document_id',
               :pending_actions => [],
               :content => {'content' => true},
               :raw => 'action',
               :metadata => {'meta' => true},
               :type => 'DocumentType',
               :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false,
               :collection_task_ids => [],
               :title => 'old_title',
               :copyright => 'old copyright',
               :display => 'old_display',
               :source => 'old_source',
               :archive_files => ['archive_file'],
               :version => 1,
               :created_timestamp => 'created',
               :document_timestamp => Time.at(1499999999),
               :error => nil)

    pub_doc = stub(:document_id => 'document_id',
                   :pending_actions => [],
                   :type => 'DocumentType',
                   :state => Armagh::Documents::DocState::PUBLISHED,
                   :deleted? => false,
                   :collection_task_ids => [],
                   :content => {'pub_cont': true},
                   :raw => 'pub',
                   :metadata => {'pub_meta' => true},
                   :created_timestamp => 'created',
                   :dev_errors => {},
                   :ops_errors => {},
                   :source => Armagh::Documents::Source.new,
                   :title => 'old title',
                   :internal_id => 'internal',
                   :display => 'old display',
                   :archive_files => ['old_archive_file'],
                   :version => 1,
                   :document_timestamp => Time.at(1500000000)
    )

    doc.expects(:to_action_document).returns(action_doc)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    doc.stubs(:delete_pending_actions_if).yields(action_name ).returns(true).then.yields( pending_actions.shift ).returns(true).then.yields(pending_actions.shift).returns(true).then.yields(nil).returns(false)
    @workflow_set.expects(:actions_names_handling_docspec).returns([action_name])
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once
    doc.expects(:add_items_to_pending_actions).with([action_name])

    doc.expects(:document_id=, action_doc.document_id)
    doc.expects(:content=, action_doc.content)
    doc.expects(:raw=, [ action_doc.raw ]).with('action')
    doc.expects(:metadata=, action_doc.metadata)
    doc.expects(:title=, action_doc.title)
    doc.expects(:copyright=, action_doc.copyright)
    doc.expects(:published_id=)
    doc.expects(:document_timestamp=)
    doc.expects(:created_timestamp=)
    doc.expects(:published_timestamp=)
    doc.expects(:delete).never
    doc.expects(:get_published_copy_read_only).returns(pub_doc)
    doc.expects(:display=).with(action_doc.display)
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:collection_task_ids).returns []
    doc.expects(:version=)
    doc.expects(:state=)

    doc.expects(:mark_publish)
    doc.expects(:raw=).with(nil)
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @logger.unstub(:dev_warn)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.expects(:abort)

    @default_agent.send(:execute)
  end

  def test_run_consume_action
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)
    action = setup_action(Armagh::StandardActions::ConsumeTest, {'action' => { 'workflow' => 'wf' }, 'input' => {'docspec' => input_docspec}})
    action_name = action.config.action.name

    published_doc = Armagh::Documents::PublishedDocument.new(document_id: 'id',
                                                             content: {'content' => 'old'},
                                                             raw: 'raw',
                                                             metadata: {'meta' => 'old'},
                                                             docspec: input_docspec,
                                                             source: {},
                                                             title: nil,
                                                             copyright: nil,
                                                             document_timestamp: nil)
    action.expects(:consume).with(published_doc)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true},
               :raw => 'raw', :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [],
               :archive_files => [], :error => nil)
    doc.expects(:to_published_document).returns(published_doc)
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once

    doc.expects(:metadata=).with published_doc.metadata

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_divider
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentDividedType', Armagh::Documents::DocState::READY)

    divider = setup_action(Armagh::StandardActions::DividerTest, {
        'action' => { 'workflow' => 'wf' },
        'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}

    })
    action_name = divider.config.action.name

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true}, :raw => nil, :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.expects(:raw=).with(nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(divider).at_least_once

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    @default_agent.expects(:report_status).with(doc, divider).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_action_with_dev_errors
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect).at_least_once

    pending_actions = [action_name]

    doc = stub(:document_id => 'document_id', :pending_actions => pending_actions, :content => 'content', :raw => nil, :metadata => {}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil, :internal_id => '123' )
    doc.stubs(:delete_pending_actions_if).yields( pending_actions.first )
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).at_least_once
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    collection = mock(name: 'published_collection')
    Armagh::Connection.stubs(:documents).returns(collection)

    doc.expects(:published?).returns(true)
    doc.expects(:type).returns('DevErrorType')

    doc.expects(:dev_errors).returns({action_name => ['BROKEN']})

    doc.expects(:mark_delete).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)

    assert_equal([action_name], pending_actions)
  end

  def test_run_action_with_ops_errors
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    action.expects(:collect).at_least_once

    pending_actions = [action_name]

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => pending_actions, :content => 'content', :raw => nil, :metadata => {}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( pending_actions.first )

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).at_least_once
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    collection = mock(name: 'documents')
    Armagh::Connection.stubs(:documents).returns(collection)

    doc.expects(:published?).returns(false)

    doc.expects(:ops_errors).returns({'action_name' => ['BROKEN']})
    doc.expects(:dev_errors).returns({})

    doc.expects(:mark_delete).at_least_once
    doc.expects(:metadata).returns({})

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)

    assert_equal([action_name], pending_actions)
  end

  def test_run_collect_abort
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name

    e = Armagh::Agent::AbortDocument.new('abort')
    action.expects(:collect).raises(e)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => 'content', :raw => 'raw data', :metadata => {}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name  ).returns(true).then.returns(false)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:mark_abort)

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:metadata).never

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action)
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)  end

  def test_run_publish_abort
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    output_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    action = setup_action(Armagh::StandardActions::PublishTest, {
        'action' => { 'workflow' => 'wf' },       'input' => {'docspec' => input_docspec},
      'output' => {'docspec' => output_docspec}
    })
    action_name = action.config.action.name
    pending_actions = %w(one two)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'old' => 'content'},
                                                       raw: 'action',
                                                       metadata: {'old' => 'meta'},
                                                       docspec: input_docspec,
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)
    e = Armagh::Agent::AbortDocument.new('abort')
    action.expects(:publish).raises(e)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => pending_actions, :content => {'content' => true},
               :raw => 'action', :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING,
               :deleted? => false, :collection_task_ids => [], archive_files: [], :source => Armagh::Documents::Source.new,
               :error => nil)
    doc.expects(:to_action_document).returns(action_doc)
    doc.stubs(:delete_pending_actions_if).yields( action_name ).returns(true).then.yields(nil).returns(false)

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:document_id=, action_doc.document_id).never
    doc.expects(:content=, action_doc.content).never
    doc.expects(:metadata=, action_doc.metadata).never
    doc.expects(:title=, action_doc.title).never
    doc.expects(:copyright=, action_doc.copyright).never
    doc.expects(:state=, Armagh::Documents::DocState::PUBLISHED).never
    doc.expects(:document_timestamp=).never
    doc.expects(:add_pending_actions).with(pending_actions).never
    doc.expects(:delete).never
    doc.expects(:mark_publish).never
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:get_published_copy).never
    doc.expects(:published_timestamp=).never
    doc.expects(:display=).never
    doc.expects(:mark_abort)

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_consume_abort
    input_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)
    action = setup_action(Armagh::StandardActions::ConsumeTest, {'action' => { 'workflow' => 'wf' }, 'input' => {'docspec' => input_docspec}})
    action_name = action.config.action.name

    published_doc = Armagh::Documents::PublishedDocument.new(document_id: 'id',
                                                             content: {'content' => 'old'},
                                                             raw: 'raw',
                                                             metadata: {'meta' => 'old'},
                                                             docspec: input_docspec,
                                                             source: {},
                                                             title: nil,
                                                             copyright: nil,
                                                             document_timestamp: nil)

    e = Armagh::Agent::AbortDocument.new('abort)')
    action.expects(:consume).raises(e)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [action_name], :content => {'content' => true},
               :raw => 'raw', :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [],
               :archive_files => [], :error => nil)
    doc.stubs(:delete_pending_actions_if).yields( action_name )
    doc.expects(:to_published_document).returns(published_doc)
    doc.expects(:finish_processing).never
    doc.expects(:mark_abort)
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:metadata=).never

    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_failed_action
    exception = RuntimeError.new
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name
    action.stubs(:collect).raises(exception)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true}, :raw => nil, :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :deleted? => false, :error => nil)

    doc.stubs(:delete_pending_actions_if).yields( action_name ).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).then.yields(nil).returns(false).at_least_once
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.stubs(:document_id).returns('doc_id')
    doc.expects(:add_dev_error)
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})

    Dir.expects(:mktmpdir).yields(@temp_dir)
    Dir.expects(:chdir).yields

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Armagh::Logging.expects(:dev_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal "Error while executing action '#{action_name}' on 'doc_id'", msg
      true
    end

    @default_agent.send(:execute)
  end

  def test_run_with_work_no_action_exists
    action_name = 'action_name'
    doc = stub(:document_id => 'document_id', :pending_actions => [])
    doc.stubs(:delete_pending_actions_if).yields( action_name )
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true)
    doc.expects(:add_ops_error).at_least_once
    doc.stubs(:error).returns(nil)
    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:raw=).with(nil)
    @backoff_mock.expects(:reset).at_least_once

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(nil).at_least_once

    @default_agent.expects(:report_status).with(doc, nil).at_least_once

    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_no_work
    Armagh::Document.expects(:get_one_for_processing_locked).returns(false).at_least_once

    @default_agent.expects(:report_status).with(nil, nil).at_least_once
    @backoff_mock.expects(:interruptible_backoff).at_least_once

    @backoff_mock.expects(:reset).never

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)
  end

  def test_run_not_action
    action = 'Not an action'
    action_name = 'action_name'

    doc = stub(:document_id => 'document_id', :pending_actions => [], :content => {'content' => true},
               :raw => nil, :metadata => {'meta' => true}, :deleted? => true, :collection_task_ids => [])

    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once

    doc.expects(:dev_errors).returns({})
    doc.expects(:ops_errors).returns({})
    doc.expects(:error).returns(nil).then.returns(true)

    doc.stubs(:delete_pending_actions_if).yields( action_name ).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).then.yields(nil).returns(false).at_least_once

    @logger.expects(:dev_error).with("#{action} is not an action.")

    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    @default_agent.send(:execute)  end

  def test_run_unexpected_error
    exception = RuntimeError.new 'Exception'
    Armagh::Document.expects(:get_one_for_processing_locked).raises(exception)

    Armagh::Logging.expects(:dev_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal 'An unexpected error occurred', msg
      true
    end

    @default_agent.instance_variable_set(:@running, true)
    @default_agent.send(:run)
  end

  def test_report_status_no_work
    time = Time.now
    Armagh::Status::AgentStatus.expects(:report).with(
        id: @agent_id,
        hostname: @hostname,
        status: Armagh::Status::IDLE,
        task: nil,
        running_since: nil,
        idle_since: anything) do |args|
      assert_in_delta(time, args[:idle_since], 1)
      true
    end.twice
    @default_agent.send(:report_status, nil, nil)
    sleep 2
    @default_agent.send(:report_status, nil, nil)
  end

  def test_report_status_with_work
    doc = stub(:document_id => 'document_id')
    action = stub(:name => 'action_id')
    time = Time.now
    times = []

    Armagh::Status::AgentStatus.expects(:report).with(
        id: @agent_id,
        hostname: @hostname,
        status: Armagh::Status::RUNNING,
        task: {'document' => 'document_id', 'action' => 'action_id'},
        running_since: time,
        idle_since: nil
    ) do |args|
      times << args[:running_since]
      true
    end.twice
    @default_agent.send(:report_status, doc, action)
    sleep 2
    @default_agent.send(:report_status, doc, action)

    assert_equal 2, times.length
    assert_not_in_delta(times[0], times[1], 1)
  end

  def test_create_document
    action = mock
    source = mock
    @current_doc_mock.expects(:document_id).returns('current_id')
    @workflow_set.expects(:actions_names_handling_docspec).returns([]).at_least_once

    @default_agent.instance_variable_set(:'@current_action', action)
    Armagh::Document.expects(:create_one_unlocked).with(
        { 'type' => 'DocumentType',
          'content' => 'content',
          'raw' => 'raw',
          'metadata' => 'metadata',
          'pending_actions' => [],
          'state' => Armagh::Documents::DocState::WORKING,
          'document_id' =>'id',
          'collection_task_ids' => [],
          'archive_files' => [],
          'title' => nil,
          'copyright' => nil,
          'document_timestamp' => nil,
          'display' => nil,
          'source' => source }
    )
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: 'content',
                                                       raw: 'raw',
                                                       metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING),
                                                       source: source,
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)
    @default_agent.create_document action_doc
  end

  def test_create_document_current
    id = 'id'
    @current_doc_mock.expects(:document_id).returns(id)
    source = mock

    action_doc = Armagh::Documents::ActionDocument.new(document_id: id, content: 'content', raw: 'raw', metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING), source: source,
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)

    e = assert_raise(Armagh::Documents::Errors::DocumentError) do
      @default_agent.create_document action_doc
    end

    assert_equal("Cannot create document 'id'.  It is the same document that was passed into the action.", e.message)
  end

  def test_create_document_uniqueness
    source = mock
    @current_doc_mock.expects(:document_id).returns('current_id')
    @workflow_set.expects(:actions_names_handling_docspec).returns([]).at_least_once
    initial_error = Armagh::Connection::DocumentUniquenessError.new('message')

    Armagh::Document.expects(:create_one_unlocked).raises(initial_error)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: 'content', raw: 'raw', metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING), source: source,
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)

    assert_raise(Armagh::Documents::Errors::DocumentUniquenessError.new(initial_error.message)){@default_agent.create_document action_doc}
  end

  def test_create_document_too_large
    source = mock
    @current_doc_mock.expects(:document_id).returns('current_id')
    @workflow_set.expects(:actions_names_handling_docspec).returns([]).at_least_once
    initial_error = Armagh::Connection::DocumentSizeError.new('message')

    Armagh::Document.expects(:create_one_unlocked).raises(initial_error)

    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id', content: 'content', raw: nil, metadata: 'metadata',
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING), source: source,
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)

    assert_raise(Armagh::Documents::Errors::DocumentSizeError.new(initial_error.message)){@default_agent.create_document action_doc}
  end

  def test_edit_document

    doc = prep_working_doc( new_document: false )
    @workflow_set.expects(:actions_names_handling_docspec).returns([]).at_least_once

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_content = {'new content' => true}
    new_raw = 'raw'
    new_meta = {'new meta' => true}
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)

    doc.expects(:clear_pending_actions)
    doc.expects(:add_pending_actions).with([])
    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: doc.document_id, content: {'content' => true},
                                                                                   raw: 'raw',
                                                                                   metadata: {'meta' => true},
                                                                                   docspec: old_docspec,
                                                                                   source: {},
                                                                                   title: nil,
                                                                                   copyright: nil,
                                                                                   document_timestamp: nil))

    doc.expects(:update_from_draft_action_document).with do |action_doc|
      assert_equal(new_content, action_doc.content)
      assert_equal(new_raw, action_doc.raw)
      assert_equal(new_meta, action_doc.metadata)
      assert_equal(new_docspec, action_doc.docspec)
      true
    end
    Armagh::Document.expects(:with_new_or_existing_locked_document).with(doc.document_id, old_docspec.type, old_docspec.state, @default_agent ).yields(doc)

    executed_block = false
    @default_agent.edit_document(doc.document_id, old_docspec) do |doc|
      assert_equal(Armagh::Documents::ActionDocument, doc.class)
      assert_false doc.new_document?
      doc.metadata = new_meta
      doc.content = new_content
      doc.raw = new_raw
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

    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    content = {'new content' => true}
    raw = 'new raw'
    meta = {'new meta' => true}

    doc = prep_working_doc( new_document: true )
    set_expectations_on_new_doc( doc, type: 'DocumentType', state: Armagh::Documents::DocState::WORKING,
                                      pending_actions: [], content: content, raw: raw, metadata: meta )
    executed_block = false
    @default_agent.edit_document(doc.document_id, docspec) do |doc|
      assert_equal(Armagh::Documents::ActionDocument, doc.class)
      doc.metadata = meta
      doc.content = content
      doc.raw = raw
      doc.docspec = docspec
      executed_block = true
    end

    assert_true executed_block
  end

  def test_edit_document_change_type
    doc = mock('document')
    doc.expects(:new_document?).returns(false)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('ChangedType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id,
                                                                                   content: 'old content',
                                                                                   raw: 'old raw',
                                                                                   metadata: 'old meta',
                                                                                   docspec: old_docspec,
                                                                                   source: {},
                                                                                   title: nil,
                                                                                   copyright: nil,
                                                                                   document_timestamp: nil))

    Armagh::Document.expects(:with_new_or_existing_locked_document).with(id, old_docspec.type, old_docspec.state, @default_agent).yields(doc)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_same_state
    doc = mock('document')
    doc.expects(:new_document?).returns(false)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id,
                                                                                   content: 'old content',
                                                                                   raw: 'old raw',
                                                                                   metadata: 'old meta',
                                                                                   docspec: docspec,
                                                                                   source: {},
                                                                                   title: nil,
                                                                                   copyright: nil,
                                                                                   document_timestamp: nil))

    doc.expects(:update_from_draft_action_document).with do |action_doc|
      assert_equal(docspec, action_doc.docspec)
      true
    end
    Armagh::Document.expects(:with_new_or_existing_locked_document).with(id, docspec.type, docspec.state, @default_agent).yields(doc)

    @default_agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_change_state_w_p
    doc = mock('document')
    doc.expects(:new_document?).returns(false)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id,
                                                                                   content: 'old content',
                                                                                   raw: 'old raw',
                                                                                   metadata: 'old meta',
                                                                                   docspec: old_docspec,
                                                                                   source: {},
                                                                                   title: nil,
                                                                                   copyright: nil,
                                                                                   document_timestamp: nil))

    Armagh::Document.expects(:with_new_or_existing_locked_document).with(id, old_docspec.type, old_docspec.state, @default_agent ).yields(doc)

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_change_state_r_w
    doc = mock('document')
    doc.expects(:new_document?).returns(false)
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    doc.expects(:to_action_document).returns(Armagh::Documents::ActionDocument.new(document_id: id,
                                                                                   content: 'content',
                                                                                   raw: 'raw',
                                                                                   metadata: 'meta',
                                                                                   docspec: old_docspec,
                                                                                   source: {},
                                                                                   title: nil,
                                                                                   copyright: nil,
                                                                                   document_timestamp: nil))

    Armagh::Document.expects(:with_new_or_existing_locked_document).with(id, old_docspec.type, old_docspec.state, @default_agent ).yields(doc)

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

    content = {'new content' => true}
    raw = 'new raw'
    meta = {'new meta' => true}

    doc = prep_working_doc( new_document: true )
    set_expectations_on_new_doc( doc, type: 'DocumentType', state: Armagh::Documents::DocState::WORKING,
                                 pending_actions: [], content: content, raw: raw, metadata: meta,
                                 expect_update_from_action_document: false )

    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(doc.document_id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' type is not changeable while editing.  Only state is.", e.message)
  end

  def test_edit_document_new_same_state
    @current_doc_mock.expects(:document_id).returns('current_id')
    id = 'id'

    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    content = {'new content' => true}
    raw = 'new raw'
    meta = {'new meta' => true}

    doc = prep_working_doc( new_document: true )
    set_expectations_on_new_doc( doc, type: 'DocumentType', state: Armagh::Documents::DocState::WORKING,
                                  pending_actions: [], content: content, raw: raw, metadata: meta )


    @default_agent.edit_document(id, docspec) do |doc|
      doc.docspec = docspec
    end
  end

  def test_edit_document_new_change_state_w_p
    id = 'id'
    @current_doc_mock.expects(:document_id).returns('current_id')

    old_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)
    new_docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::PUBLISHED)

    content = {'new content' => true}
    raw = 'new raw'
    meta = {'new meta' => true}

    doc = prep_working_doc( new_document: true )
    set_expectations_on_new_doc( doc, type: 'DocumentType', state: Armagh::Documents::DocState::WORKING,
                                 pending_actions: [], content: content, raw: raw, metadata: meta,
                                 expect_update_from_action_document: false )

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

    content = {'new content' => true}
    raw = 'new raw'
    meta = {'new meta' => true}

    doc = prep_working_doc( new_document: true )
    set_expectations_on_new_doc( doc, type: 'DocumentType', state: Armagh::Documents::DocState::READY,
                                 pending_actions: [], content: content, raw: raw, metadata: meta,
                                 expect_update_from_action_document: false )


    e = assert_raise(Armagh::Documents::Errors::DocSpecError) do
      @default_agent.edit_document(id, old_docspec) do |doc|
        doc.docspec = new_docspec
      end
    end

    assert_equal("Document 'id' state can only be changed from working to ready.", e.message)
  end

  def test_edit_document_uniqueness
    @current_doc_mock.expects(:document_id).returns('current_id')

    initial_error = Armagh::Connection::DocumentUniquenessError.new('message')
    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:with_new_or_existing_locked_document).raises(initial_error)

    assert_raise(Armagh::Documents::Errors::DocumentUniquenessError.new(initial_error.message)) do
      @default_agent.edit_document('id', docspec) do |doc|
        doc.metadata['something'] = 'value'
      end
    end
  end

  def test_edit_document_too_large
    @current_doc_mock.expects(:document_id).returns('current_id')

    initial_error = Armagh::Connection::DocumentSizeError.new('message')
    docspec = Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects(:with_new_or_existing_locked_document).raises(initial_error)

    assert_raise(Armagh::Documents::Errors::DocumentSizeError.new(initial_error.message)) do
      @default_agent.edit_document('id', docspec) do |doc|
        doc.metadata['something'] = 'value'
      end
    end
  end

  def test_abort
    assert_raise(Armagh::Agent::AbortDocument){@default_agent.abort}
  end

  def test_get_existing_published_document
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'content' => true},
                                                       raw: nil,
                                                       metadata: {'meta' => true},
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY),
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: Time.at(12345))
    doc = mock('db doc')
    pub_action_doc = mock
    doc.expects(:to_published_document).returns(pub_action_doc)

    Armagh::Document.expects(:find_one_by_document_id_type_state_read_only).returns(doc)
    assert_equal(pub_action_doc, @default_agent.get_existing_published_document(action_doc))
  end

  def test_get_existing_published_document_none
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'id',
                                                       content: {'content' => true},
                                                       raw: nil,
                                                       metadata: {'meta' => true},
                                                       docspec: Armagh::Documents::DocSpec.new('DocumentType', Armagh::Documents::DocState::READY),
                                                       source: {},
                                                       title: nil,
                                                       copyright: nil,
                                                       document_timestamp: nil)
    Armagh::Document.expects(:find_one_by_document_id_type_state_read_only).returns(nil)
    assert_nil @default_agent.get_existing_published_document(action_doc)
  end

  def test_log_debug
    message = 'test message'
    logger_name = 'test_logger'
    logger = mock('logger')
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    logger.expects(:debug).with(message)
    @default_agent.log_debug(logger_name, message)
  end

  def test_log_debug_block
    logger_name = 'test_logger'
    logger = FakeBlockLogger.new
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger).yields(nil)
    block_called = false
    @default_agent.log_debug(logger_name) { block_called = true }
    assert_true block_called
    assert_equal(:debug, logger.method)
  end

  def test_log_info
    message = 'test message'
    logger_name = 'test_logger'
    logger = mock('logger')
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    logger.expects(:info).with(message)
    @default_agent.log_info(logger_name, message)
  end

  def test_log_info_block
    logger_name = 'test_logger'
    logger = FakeBlockLogger.new
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger).yields(nil)
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
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    @current_doc_mock.expects(:add_ops_error).with(action_name, message)
    logger.expects(:ops_error).with(message)
    @default_agent.notify_ops(logger_name, action_name, message)
  end

  def test_notify_dev
    logger_name = 'logger'
    action_name = 'action'
    message = 'message'
    logger = mock
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    @current_doc_mock.expects(:add_dev_error).with(action_name, message)
    logger.expects(:dev_error).with(message)
    @default_agent.notify_dev(logger_name, action_name, message)
  end

  def test_notify_ops_exception
    logger_name = 'logger'
    action_name = 'action'
    error = RuntimeError.new('error')
    logger = mock
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    @current_doc_mock.expects(:add_ops_error).with(action_name, error)
    Armagh::Logging.expects(:ops_error_exception).with(logger, error, 'Notify Ops')
    @default_agent.notify_ops(logger_name, action_name, error)
  end

  def test_notify_dev_exception
    logger_name = 'logger'
    action_name = 'action'
    error = RuntimeError.new('error')
    logger = mock
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    @current_doc_mock.expects(:add_dev_error).with(action_name, error)
    Armagh::Logging.expects(:dev_error_exception).with(logger, error, 'Notify Dev')
    @default_agent.notify_dev(logger_name, action_name, error)
  end

  def test_get_logger
    logger_name = 'test_logger'
    logger = mock('logger')
    Armagh::Logging.expects(:set_logger).with{|name| name.include? logger_name}.returns(logger)
    assert_equal logger, @default_agent.get_logger(logger_name)
  end

  def test_archive
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    archive_data = {'something' => 'details'}
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, archive_data)

    @default_agent.archive(logger_name, action_name, file_path, archive_data)
  end

  def test_archive_archive_error
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    archive_data = {'something' => 'details'}
    error = Armagh::Utils::Archiver::ArchiveError.new('archive_error')
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, archive_data).raises(error)
    @default_agent.expects(:notify_dev).with(logger_name, action_name, error)

    @default_agent.archive(logger_name, action_name, file_path, archive_data)
  end

  def test_archive_sftp_error
    logger_name = 'test_logger'
    action_name = 'test_action'
    file_path = 'file'
    archive_data = {'something' => 'details'}
    error = Armagh::Support::SFTP::SFTPError.new('sftp error')
    archiver = @default_agent.instance_variable_get(:@archiver)
    archiver.expects(:archive_file).with(file_path, archive_data).raises(error)
    @default_agent.expects(:notify_ops).with(logger_name, action_name, error)

    @default_agent.archive(logger_name, action_name, file_path, archive_data)
  end

  def test_instantiate_divider
    divider = mock('divider')
    other = mock('other')

    config = mock('config')
    action_config = mock('action_config')
    divider.stubs(:config).returns(config)
    config.stubs(:action).returns(action_config)
    action_config.stubs(:workflow).returns('workflow')
    divider.stubs(:name).returns('name')
    divider.stubs(:class).returns(Armagh::StandardActions::DividerTest)
    divider.expects(:is_a?).with(Armagh::Actions::Divide).returns(true)
    Armagh::Actions.stubs(:defined_actions).returns([divider.class])
    other.expects(:is_a?).with(Armagh::Actions::Divide).returns(false)

    docspec = Armagh::Documents::DocSpec.new('something', Armagh::Documents::DocState::READY)
    @workflow_set.expects(:instantiate_actions_handling_docspec).with(docspec, @default_agent, @logger).returns([other, divider])
    assert_equal(divider, @default_agent.instantiate_divider(docspec))
  end

  def test_instantiate_divider_none
    docspec = Armagh::Documents::DocSpec.new('something', Armagh::Documents::DocState::READY)
    @workflow_set.expects(:instantiate_actions_handling_docspec).with(docspec, @default_agent, @logger).returns([])
    @default_agent.instantiate_divider(docspec)
  end

  def test_instantiate_divider_error
    docspec = Armagh::Documents::DocSpec.new('something', Armagh::Documents::DocState::READY)
    @workflow_set.expects(:instantiate_actions_handling_docspec).with(docspec, @default_agent, @logger).raises(Armagh::Actions::ActionInstantiationError.new('error'))
    Armagh::Logging.expects(:ops_error_exception)
    @default_agent.instantiate_divider(docspec)
  end

  def test_too_large
    exception = Armagh::Documents::Errors::DocumentSizeError.new('too large')
    action = setup_action(Armagh::StandardActions::CollectTest, {
      'action' => {'name' => 'testc', 'workflow' => 'wf'},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false},
      'input' => {'docspec' => '__COLLECT__testc:ready'},
      'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name
    action.stubs(:collect).raises(exception)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true}, :raw => 'raw',
               :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :deleted? => false,
               :dev_errors => [], :ops_errors => [], :error => nil
    )

    doc.stubs(:delete_pending_actions_if).yields( action_name ).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).then.yields(nil).returns(false).at_least_once
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:add_ops_error)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once

    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Armagh::Logging.expects(:ops_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal "Error while executing action '#{action_name}' on 'document_id'", msg
      true
    end

    @default_agent.expects(:execute_action).raises(exception)
    @default_agent.send(:execute)
  end

  def test_too_large_raw
    exception = Armagh::Documents::Errors::DocumentRawSizeError.new('too large')
    action = setup_action(Armagh::StandardActions::CollectTest, {
        'action' => {'name' => 'testc', 'workflow' => 'wf'},
        'collect' => {'schedule' => '0 * * * *', 'archive' => false},
        'input' => {'docspec' => '__COLLECT__testc:ready'},
        'output' => {'docspec' => 'dancollected:ready'}
    })
    action_name = action.config.action.name
    action.stubs(:collect).raises(exception)

    doc = stub(:internal_id => '123', :document_id => 'document_id', :pending_actions => [], :content => {'content' => true}, :raw => 'raw',
               :metadata => {'meta' => true}, :type => 'DocumentType', :state => Armagh::Documents::DocState::WORKING, :deleted? => false,
               :dev_errors => [], :ops_errors => [], :error => nil
    )

    doc.stubs(:delete_pending_actions_if).yields( action_name ).returns(true).then.yields(nil).returns(false)
    Armagh::Document.expects(:get_one_for_processing_locked).yields(doc).returns(true).then.yields(nil).returns(false).at_least_once
    @workflow_set.expects(:instantiate_action_named).with(action_name, @default_agent, @logger).returns(action).at_least_once

    doc.expects(:add_ops_error)

    @default_agent.expects(:report_status).with(doc, action).at_least_once
    doc.expects(:raw=, [ '(nil)' ]).with(nil).at_least_once

    @backoff_mock.expects(:reset).at_least_once

    @default_agent.instance_variable_set(:@running, true)

    Armagh::Logging.expects(:ops_error_exception).with do |_logger, e, msg|
      assert_equal exception, e
      assert_equal "Error while executing action '#{action_name}' on 'document_id'", msg
      true
    end

    @default_agent.expects(:execute_action).raises(exception)
    @default_agent.send(:execute)
  end

  def test_with_locked_action_state

    action_name = 'my_action'
    @state_coll.stubs( find_one_and_update: nil, find: mock( limit: [] ))
    @state_coll.expects( :insert_one ).with() { |image|
      image[ 'action_name' ] == action_name
    }.returns( mock( inserted_ids: [ 'id123']))
    state_doc = Armagh::ActionStateDocument.send(:new, {'action_name' => action_name })

    @state_coll.expects( :replace_one ).with() { |qualifier, image|
      qualifier['$and'].include?( { '_id' => 'id123'}) &&
      image[ 'action_name' ] == action_name &&
      image[ '_locked' ] == false
    }.returns( mock( modified_count: 1 ))
    @default_agent.with_locked_action_state( action_name, lock_hold_duration: 90 ) do |state_hash|
      assert_equal( {}, state_hash)
      state_hash[ 'this' ] = 'is new content'
    end
  end

  def test_with_locked_action_state_no_block
    action_name = 'my_action'
    @state_coll.stubs( find_one_and_update: nil, find: mock( limit: [] ))
    @state_coll.expects( :insert_one ).with() { |image|
      image[ 'action_name' ] == action_name
    }.returns( mock( inserted_ids: [ 'id123']))
    state_doc = Armagh::ActionStateDocument.send(:new, {'action_name' => action_name })

    @state_coll.expects( :replace_one ).with() { |qualifier, image|
      qualifier['$and'].include?( { '_id' => 'id123'}) &&
          image[ 'action_name' ] == action_name &&
          image[ '_locked' ] == false
    }.returns( mock( modified_count: 1 ))

    assert_raises( LocalJumpError ) do
      @default_agent.with_locked_action_state( action_name, lock_hold_duration: 90 )
    end
  end
end
