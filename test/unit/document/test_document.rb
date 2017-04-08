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

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/document/document'

require 'armagh/documents/doc_state'

require 'log4r'

require 'test/unit'
require 'mocha/test_unit'

class TestDocument < Test::Unit::TestCase

  include Armagh

  def setup
    @documents = mock('documents')
    @internal_id = 'internal_id'
    mock_document_insert(@internal_id)
    Armagh::Connection.stubs(:documents).returns(@documents)
    Armagh::Connection.stubs(:all_document_collections).returns([@documents])
    @doc = Document.create(type: 'testdoc',
                           content: {'content' => true},
                           metadata: {'meta' => true},
                           pending_actions: [],
                           state: Armagh::Documents::DocState::WORKING,
                           document_id: 'id',
                           collection_task_ids: [],
                           document_timestamp: Time.new(2016, 1, 1, 0, 0, 0, 0).utc)
  end

  def test_new
    assert_raise(NoMethodError) { Document.new }
    doc = Document.send(:new)
    assert_instance_of(Document, doc)
  end

  def mock_document_insert(id)
    insertions = stub(inserted_ids: [id])
    @documents.stubs(insert_one: insertions)
  end

  def mock_document_replace
    @documents.stubs(replace_one: nil)
  end

  def mock_document_delete
    @documents.stubs(delete_one: nil)
  end

  def mock_document_find(result)
    find_result = mock('object')
    find_result.expects(:limit).with(1).returns([result].flatten)
    @documents.stubs(:find => find_result)
  end

  def mock_document_find_one_and_update(result)
    @documents.stubs(:find_one_and_update => result)
  end

  def mock_document_update_one
    @documents.stubs(:update_one => nil)
  end

  def test_create_with_id
    mock_document_replace
    doc = Document.create(type: 'testdoc',
                          content: {'content' => true},
                          metadata: {'meta' => true},
                          pending_actions: [],
                          state: Armagh::Documents::DocState::WORKING,
                          document_id: 'id',
                          collection_task_ids: [],
                          document_timestamp: Time.new(2016, 1, 1, 0, 0, 0, 0).utc,
                          archive_files: ['whatever'],
    )

    assert_equal('testdoc', doc.type)
    assert_equal({'content' => true}, doc.content)
    assert_equal({'meta' => true}, doc.metadata)
    assert_equal('id', doc.document_id)
    assert_equal(['whatever'], doc.archive_files)
    assert_equal(@internal_id, doc.internal_id)
  end

  def test_create_trigger_document
    @documents.expects(:update_one)
    Document.create_trigger_document(state: Documents::DocState::READY, type: 'type', pending_actions: [])
  end

  def test_create_trigger_document_error
    e = RuntimeError.new('error')
    @documents.expects(:update_one).raises(e)
    assert_raise(e) { Document.create_trigger_document(state: Documents::DocState::READY, type: 'type', pending_actions: []) }
  end

  def test_from_action_document
    id = 'id'
    content = 'blah'
    metadata = 'draft_meta'
    docspec = Documents::DocSpec.new('document type', Armagh::Documents::DocState::READY)
    new_doc = true
    pending_actions = %w(pend1 pend2)
    source = {'some' => 'source'}
    display = 'display'
    title = 'title'
    copyright = 'copyright'
    document_timestamp = Time.at(0)
    action_doc = Armagh::Documents::ActionDocument.new(document_id: id,
                                                       content: content,
                                                       metadata: metadata,
                                                       title: title,
                                                       docspec: docspec,
                                                       new: new_doc,
                                                       source: source,
                                                       display: display,
                                                       copyright: copyright,
                                                       document_timestamp: document_timestamp)
    doc = Document.from_action_document(action_doc, pending_actions)

    assert_equal(id, doc.document_id)
    assert_equal(content, doc.content)
    assert_equal(metadata, doc.metadata)
    assert_equal(docspec.type, doc.type)
    assert_equal(docspec.state, doc.state)
    assert_equal(pending_actions, doc.pending_actions)
    assert_equal(source, doc.source)
    assert_equal(display, doc.display)
    assert_equal(title, doc.title)
    assert_equal(copyright, doc.copyright)
    assert_equal(document_timestamp, doc.document_timestamp)
  end

  def test_find
    mock_document_find({'document_id' => 'docid'})
    doc = Document.find('docid', 'testdoc', Documents::DocState::READY)
    assert_equal('docid', doc.document_id)
  end

  def test_find_none
    mock_document_find([])
    doc = Document.find('id', 'testdoc', Documents::DocState::WORKING)
    assert_nil(doc)
  end

  def test_find_error
    e = Mongo::Error.new('error')
    @documents.expects(:find).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.find('id', 'testdoc', Documents::DocState::WORKING) }
  end

  def test_get_for_processing
    mock_document_find_one_and_update({'document_id' => 'docid'})
    doc = Document.get_for_processing('agent-123')
    assert_equal('docid', doc.document_id)
  end

  def test_get_for_processing_error
    e = Mongo::Error.new('error')
    @documents.expects(:find_one_and_update).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.get_for_processing('agent-123') }
  end

  def test_exists?
    mock_document_find([1])
    assert_true Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING)

    mock_document_find([])
    assert_false Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING)
  end

  def test_exists_error
    e = Mongo::Error.new('error')
    @documents.expects(:find).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING) }
  end


  def test_pending_actions
    pending_actions = %w(Action1 Action2 Action3)
    assert_empty(@doc.pending_actions)
    assert_false(@doc.pending_work?)

    @doc.add_pending_actions(pending_actions)
    assert_equal(3, @doc.pending_actions.length)
    assert_true(@doc.pending_work?)

    pending_actions.each_with_index do |action, idx|
      @doc.remove_pending_action(action)
      assert_equal(3-(1+idx), @doc.pending_actions.length)
    end
    assert_false(@doc.pending_work?)

    @doc.add_pending_actions(pending_actions)
    assert_true @doc.pending_work?
    @doc.clear_pending_actions
    assert_false @doc.pending_work?
    assert_empty @doc.pending_actions
  end

  def test_dev_errors
    assert_empty(@doc.dev_errors)
    assert_false @doc.error?

    failures = [
      {name: 'failed_action', details: RuntimeError.new('runtime error')},
      {name: 'failed_action2', details: 'string error'},
    ]
    failures.each { |f| @doc.add_dev_error(f[:name], f[:details]) }

    assert_equal(2, @doc.dev_errors.length)
    assert_true @doc.error?

    failures.each do |failure|
      name = failure[:name]
      details = failure[:details]

      assert_true(@doc.dev_errors.has_key? name)
      db_details = @doc.dev_errors[name].first
      if details.is_a? Exception
        assert_equal(details.message, db_details['message'])
        assert_equal(details.backtrace, db_details['trace'])
      else
        assert_equal(details, db_details['message'])
      end

      @doc.remove_dev_error(name)
      assert_false(@doc.dev_errors.has_key?(name))
    end

    assert_empty @doc.dev_errors
    assert_false @doc.error?

    failures.each { |f| @doc.add_dev_error(f[:name], f[:details]) }

    assert_true @doc.error?

    @doc.clear_dev_errors
    assert_false @doc.error?
    assert_empty @doc.dev_errors
  end

  def test_ops_errors
    assert_empty(@doc.ops_errors)
    assert_false @doc.error?

    failures = [
      {name: 'failed_action', details: RuntimeError.new('runtime error')},
      {name: 'failed_action2', details: 'string error'},
    ]
    failures.each { |f| @doc.add_ops_error(f[:name], f[:details]) }

    assert_equal(2, @doc.ops_errors.length)
    assert_true @doc.error?

    failures.each do |failure|
      name = failure[:name]
      details = failure[:details]

      assert_true(@doc.ops_errors.has_key? name)
      db_details = @doc.ops_errors[name].first
      if details.is_a? Exception
        assert_equal(details.message, db_details['message'])
        assert_equal(details.backtrace, db_details['trace'])
      else
        assert_equal(details, db_details['message'])
      end

      @doc.remove_ops_error(name)
      assert_false(@doc.ops_errors.has_key?(name))
    end

    assert_empty @doc.ops_errors
    assert_false @doc.error?

    failures.each { |f| @doc.add_ops_error(f[:name], f[:details]) }

    assert_true @doc.error?

    @doc.clear_ops_errors
    assert_false @doc.error?
    assert_empty @doc.ops_errors
  end

  def test_pending_and_failed
    assert_false @doc.pending_work?
    assert_false @doc.error?

    pending_actions = %w(Action1 Action2 Action3)
    @doc.add_pending_actions pending_actions

    assert_true @doc.pending_work?
    assert_false @doc.error?

    failures = [
      {name: 'failed_action', details: RuntimeError.new('runtime error')},
      {name: 'failed_action2', details: 'string error'},
    ]
    failures.each { |f| @doc.add_dev_error(f[:name], f[:details]) }

    assert_false @doc.pending_work?
    assert_true @doc.error?

    @doc.clear_dev_errors

    assert_true @doc.pending_work?
    assert_false @doc.error?

    @doc.clear_pending_actions
    assert_false @doc.pending_work?
    assert_false @doc.error?
  end

  def test_ids
    doc_id = 'docid'
    internal = 'internal_id
'
    assert_not_equal(doc_id, @doc.document_id)
    @doc.document_id = doc_id
    assert_equal(doc_id, @doc.document_id)

    assert_not_equal(internal, @doc.internal_id)
    @doc.internal_id = internal
    assert_equal(internal, @doc.internal_id)
  end

  def test_timestamps
    mock_document_replace
    doc = Document.create(type: 'testdoc',
                          content: {'content' => true},
                          metadata: {'meta' => true},
                          pending_actions: [],
                          state: Armagh::Documents::DocState::WORKING,
                          document_id: 'id',
                          collection_task_ids: [],
                          document_timestamp: Time.now)
    assert_in_delta(Time.now, doc.created_timestamp, 1)
    assert_equal(doc.created_timestamp, doc.updated_timestamp)

    sleep 1
    created_timestamp = doc.created_timestamp
    doc.content = 'New draft content'
    doc.save
    assert_equal(created_timestamp, doc.created_timestamp)
    assert_not_equal(doc.created_timestamp, doc.updated_timestamp)
    assert_true(doc.created_timestamp < doc.updated_timestamp)

    t = Time.now
    assert_not_equal(t, doc.published_timestamp)
    doc.published_timestamp = t
    assert_equal(doc.published_timestamp, t)

    assert_not_equal(t, doc.created_timestamp)
    doc.created_timestamp = t
    assert_equal(doc.created_timestamp, t)

    update = t + 100
    assert_not_equal(update, doc.created_timestamp)
    doc.updated_timestamp = update
    assert_equal(doc.updated_timestamp, update)
  end

  def test_collection_task_ids
    assert_empty @doc.collection_task_ids
    @doc.collection_task_ids = [1]
    @doc.collection_task_ids << 2
    assert_equal([1, 2], @doc.collection_task_ids)
  end

  def test_finish_processing
    logger = mock('logger')
    mock_document_replace
    @doc.finish_processing(logger)
    assert_false @doc.locked?
  end

  def test_state
    assert_not_equal(Documents::DocState::PUBLISHED, @doc.state)
    @doc.state = Documents::DocState::PUBLISHED
    assert_equal(Documents::DocState::PUBLISHED, @doc.state)
  end

  def test_invalid_state
    e = assert_raise(Armagh::Documents::Errors::DocStateError) { @doc.state = 'this is an invalid state' }
    assert_equal(e.message, "Tried to set state to an unknown state: 'this is an invalid state'.")
  end

  def test_working?
    @doc.state = Documents::DocState::PUBLISHED
    assert_false @doc.working?
    @doc.state = Documents::DocState::WORKING
    assert_true @doc.working?
  end

  def test_ready?
    @doc.state = Documents::DocState::PUBLISHED
    assert_false @doc.ready?
    @doc.state = Documents::DocState::READY
    assert_true @doc.ready?
  end

  def test_published?
    @doc.state = Documents::DocState::WORKING
    assert_false @doc.published?
    @doc.state = Documents::DocState::PUBLISHED
    assert_true @doc.published?
  end

  def test_modify_or_create_new
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    mock_document_find_one_and_update({'_id' => 'id', 'locked' => true})
    mock_document_delete
    block_executed = false

    Document.modify_or_create(id, type, state, true, 'agent-123') do |doc|
      assert_kind_of(String, doc)
      block_executed = true
    end

    assert_true block_executed
  end

  def test_modify_or_create_existing
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    mock_document_find_one_and_update({'_id' => id, 'content' => {'doc content' => true}, 'metadata' => {'meta' => true}, 'type' => type, 'state' => state})
    mock_document_replace
    block_executed = false

    Document.modify_or_create(id, type, state, true, 'agent-123') do |doc|
      assert_not_nil doc
      block_executed = true
    end

    assert_true block_executed
  end

  def test_modify_or_create_locked
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'E11000 duplicate key error').at_least_once


    # Have to bail out of the infinite loop somehow
    e = RuntimeError.new
    Utils::ProcessingBackoff.any_instance.expects(:interruptible_backoff).raises(e)

    block_executed = false

    assert_raise(e) do
      Document.modify_or_create(id, type, state, false, 'agent-123') do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_or_create_unexpected_error
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'Unknown')


    block_executed = false

    assert_raise(Armagh::Errors::ConnectionError.new("An unexpected connection error occurred from Document 'docid': Unknown.")) do
      Document.modify_or_create(id, type, state, true, 'agent-123') do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_or_create_no_block
    assert_raise(LocalJumpError) do
      Document.modify_or_create('id', 'type', Armagh::Documents::DocState::WORKING, true, 'agent-123')
    end
  end

  def test_modify_or_create_new_error
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    Document.expects(:delete)
    mock_document_find_one_and_update({'_id' => 'docid', 'locked' => 'true'})

    e = RuntimeError.new 'Error'
    assert_raise(e) do
      Document.modify_or_create(id, type, state, true, 'agent-123') do |doc|
        raise e
      end
    end
  end

  def test_modify_or_create_existing_error
    id = 'docid'
    type = 'testdoc'
    state = Documents::DocState::WORKING
    mock_document_find_one_and_update({'_id' => id, 'content' => {'doc content' => true}, 'metadata' => {'doc meta' => true}, 'type' => type, 'state' => state, 'pending_actions' => []})
    Document.expects(:unlock)

    e = RuntimeError.new 'Error'
    assert_raise(e) do
      Document.modify_or_create(id, type, state, true, 'agent-123') do |doc|
        raise e
      end
    end
  end

  def test_delete
    @documents.expects(:delete_one).with({:'document_id' => '123'})
    Document.delete('123', 'type', 'state')
  end

  def test_delete_error
    e = Mongo::Error.new('error')
    @documents.expects(:delete_one).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.delete('123', 'type', 'state') }
  end

  def test_get_published_copy
    pub_copy = {'document_id' => 'id'}
    mock_document_find pub_copy
    found = @doc.get_published_copy
    assert_equal('id', found.document_id)
  end

  def test_to_draft_action_document
    action_doc = @doc.to_action_document
    assert_equal(@doc.content, action_doc.content)
    assert_equal(@doc.metadata, action_doc.metadata)
    assert_equal(@doc.state, action_doc.docspec.state)
    assert_equal(@doc.type, action_doc.docspec.type)
    assert_equal(@doc.source, action_doc.source.to_hash.delete_if { |k, v| v.nil? })
  end

  def test_to_published_document
    pub_doc = @doc.to_published_document
    assert_equal(@doc.content, pub_doc.content)
    assert_equal(@doc.metadata, pub_doc.metadata)
    assert_equal(@doc.state, pub_doc.docspec.state)
    assert_equal(@doc.type, pub_doc.docspec.type)
    assert_equal(@doc.source, pub_doc.source.to_hash.delete_if { |k, v| v.nil? })
  end

  def test_update_from_draft_action_document
    id = 'id'
    content = 'new content'
    metadata = 'new meta'
    source = {'some' => 'source'}
    title = 'title'
    copyright = 'copyright'
    document_timestamp = Time.at(13249)

    docspec = Documents::DocSpec.new('type', Armagh::Documents::DocState::PUBLISHED)

    action_document = Armagh::Documents::ActionDocument.new(document_id: id,
                                                            content: content,
                                                            metadata: metadata,
                                                            docspec: docspec,
                                                            source: source,
                                                            title: title,
                                                            copyright: copyright,
                                                            document_timestamp: document_timestamp)

    assert_not_equal(content, @doc.content)
    assert_not_equal(metadata, @doc.metadata)
    assert_not_equal(docspec.type, @doc.type)
    assert_not_equal(docspec.state, @doc.state)
    assert_not_equal(title, @doc.title)
    assert_not_equal(copyright, @doc.copyright)
    assert_not_equal(document_timestamp, @doc.document_timestamp)

    @doc.update_from_draft_action_document(action_document)

    assert_equal(content, @doc.content)
    assert_equal(metadata, @doc.metadata)
    assert_equal(docspec.type, @doc.type)
    assert_equal(docspec.state, @doc.state)
    assert_equal(title, @doc.title)
    assert_equal(copyright, @doc.copyright)
    assert_equal(document_timestamp, @doc.document_timestamp)
  end

  def test_locked?
    assert_false @doc.locked?
    @doc.instance_variable_get(:@db_doc)['locked'] = 'Some-agent'
    assert_true @doc.locked?
  end

  def test_locked_by
    agent_name = 'agent-name'
    assert_nil @doc.locked_by
    @doc.instance_variable_get(:@db_doc)['locked'] = agent_name
    assert_equal(agent_name, @doc.locked_by)
  end

  def test_publish_save
    testdoc_collection = mock
    Armagh::Connection.expects(:documents).with('testdoc').returns(testdoc_collection)
    testdoc_collection.expects(:replace_one)
    @documents.expects(:delete_one).with({'_id': @doc.internal_id})

    #Armagh::Utils::EncodingHelper.expects(:fix_encoding).returns(@doc.instance_variable_get(:@db_doc))

    assert_false @doc.instance_variable_get(:@pending_publish)
    @doc.mark_publish
    assert_true @doc.instance_variable_get(:@pending_publish)
    @doc.published_id = 123
    @doc.save
    assert_false @doc.instance_variable_get(:@pending_publish)
    assert_nil @doc.published_id
  end

  def test_archive_save
    archive_collection = mock
    Armagh::Connection.expects(:collection_history).returns(archive_collection)
    archive_collection.expects(:replace_one)
    @documents.expects(:delete_one).with({'_id': @internal_id})

    assert_false @doc.instance_variable_get(:@pending_collection_history)
    @doc.mark_collection_history
    assert_true @doc.instance_variable_get(:@pending_collection_history)
    @doc.save
    assert_false @doc.instance_variable_get(:@pending_collection_history)
  end

  def test_delete_save
    @documents.expects(:delete_one).with({'_id': @doc.internal_id})

    assert_false @doc.instance_variable_get(:@pending_delete)
    @doc.mark_delete
    assert_true @doc.instance_variable_get(:@pending_delete)
    @doc.save
    assert_false @doc.instance_variable_get(:@pending_delete)
  end

  def test_published_save
    @documents.expects(:replace_one)

    doc = Document.create(type: 'testdoc',
                          content: {'content' => true},
                          metadata: {'meta' => true},
                          pending_actions: [],
                          state: Armagh::Documents::DocState::PUBLISHED,
                          document_id: 'docid',
                          collection_task_ids: [],
                          document_timestamp: Time.now)
    doc.save
  end

  def test_failed_action_save
    failures = mock('failures')
    Armagh::Connection.expects(:failures).returns(failures)
    @documents.expects(:delete_one).with({'_id': @doc.internal_id})
    failures.expects(:replace_one)

    @doc.add_dev_error('test_action', 'Failure Details')
    @doc.save
  end

  def test_too_large
    @documents.expects(:insert_one).raises(Mongo::Error::MaxBSONSize)

    error = assert_raise(Documents::Errors::DocumentSizeError) do
      Document.create(type: 'testdoc',
                      content: {'content' => true},
                      metadata: {'meta' => true},
                      pending_actions: [],
                      state: Armagh::Documents::DocState::PUBLISHED,
                      document_id: 'id',
                      new: true,
                      collection_task_ids: [],
                      document_timestamp: Time.now)
    end


    assert_equal "Document 'id' is too large.  Consider using a divider or splitter to break up the document.", error.message
  end

  def test_duplicate
    @documents.expects(:insert_one).raises(Mongo::Error::OperationFailure.new('E11000 Some context'))

    error = assert_raise(Documents::Errors::DocumentUniquenessError) do
      Document.create(type: 'testdoc',
                      content: {'content' => true},
                      metadata: {'meta' => true},
                      pending_actions: [],
                      state: Armagh::Documents::DocState::PUBLISHED,
                      document_id: 'id',
                      new: true,
                      collection_task_ids: [],
                      document_timestamp: Time.now)
    end

    assert_equal "Unable to create Document 'id'.  This document already exists.", error.message
  end

  def test_unknown_operation_error
    error = Mongo::Error::OperationFailure.new('Something')
    @documents.expects(:insert_one).raises(error)

    assert_raise(Armagh::Errors::ConnectionError.new("An unexpected connection error occurred from Document 'id': Something.")) do
      Document.create(type: 'testdoc',
                      content: {'content' => true},
                      metadata: {'meta' => true},
                      pending_actions: [],
                      state: Armagh::Documents::DocState::PUBLISHED,
                      document_id: 'id',
                      new: true,
                      collection_task_ids: [],
                      document_timestamp: Time.now)
    end
  end

  def test_class_version
    version = '12345abcdefh'
    Armagh::Document.version['armagh'] = version
    assert_equal({'armagh' => version}, Armagh::Document.version)
  end

  def test_version
    mock_document_replace
    version = '12345abcdefh'
    Armagh::Document.version['armagh'] = version
    @doc.save
    assert_equal({'armagh' => version}, @doc.version)
  end

  def test_clear_errors
    @doc.add_dev_error('test', 'test')
    @doc.add_ops_error('test', 'test')
    assert_false @doc.dev_errors.empty?
    assert_false @doc.ops_errors.empty?
    @doc.clear_errors
    assert_true @doc.dev_errors.empty?
    assert_true @doc.ops_errors.empty?
  end

  def test_unlock
    @documents.expects(:find_one_and_update).with({'document_id': 'id','type' => 'type'}, {'$set' => {'locked' => false}})
    Document.unlock('id', 'type', Armagh::Documents::DocState::PUBLISHED)
  end

  def test_unlock_error
    e = Mongo::Error.new('error')
    @documents.expects(:find_one_and_update).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.unlock('id', 'type', Armagh::Documents::DocState::PUBLISHED) }
  end

  def test_force_unlock
    @documents.expects(:update_many).with({'locked' => 'agent_id'},{'$set' => {'locked' => false}})
    Document.force_unlock('agent_id')
  end

  def test_force_unlock_error
    e = Mongo::Error.new('error')
    @documents.expects(:update_many).raises(e)
    assert_raise(Armagh::Errors::ConnectionError) { Document.force_unlock('id') }
  end

  def test_failures
    failures = mock('failures')
    failures.stubs(:find => [{'document_id' => 'fail id'}])
    Armagh::Connection.stubs(:failures).returns(failures)

    found_failures = Document.failures()
    assert_equal 1, found_failures.length
    assert_kind_of Document, found_failures.first
    assert_equal 'fail id', found_failures.first.document_id
  end

  def test_raw_failures
    failures = mock('failures')
    failures.stubs(:find => [{'document_id' => 'raw fail id'}])
    Armagh::Connection.stubs(:failures).returns(failures)
    assert_equal([{'document_id' => 'raw fail id'}], Document.failures(raw: true))
  end

  def test_to_json
    expected = {
      metadata: @doc.metadata,
      content: @doc.content,
      type: @doc.type,
      locked: @doc.locked?,
      pending_actions: @doc.pending_actions,
      dev_errors: @doc.dev_errors,
      ops_errors: @doc.ops_errors,
      created_timestamp: @doc.created_timestamp,
      updated_timestamp: @doc.updated_timestamp,
      collection_task_ids: @doc.collection_task_ids,
      archive_files: @doc.archive_files,
      source: @doc.source,
      document_timestamp: @doc.document_timestamp,
      document_id: @doc.document_id,
      state: @doc.state,
      version: @doc.version,
      _id: @doc.internal_id
    }.to_json
    assert_equal(expected, @doc.to_json)
  end
end
