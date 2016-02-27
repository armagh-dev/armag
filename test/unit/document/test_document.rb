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
require_relative '../../../lib/document/document'

require 'armagh/documents/doc_state'

require 'test/unit'
require 'mocha/test_unit'

class TestDocument < Test::Unit::TestCase

  include Armagh

  def setup
    @documents = mock
    mock_document_insert('id')
    Armagh::Connection.stubs(:documents).returns(@documents)
    @doc = Document.create('testdoc', 'draft_content', 'published_content', {'meta' => true}, [], Armagh::DocState::WORKING)
  end

  def test_new
    assert_raise(NoMethodError) {Document.new}
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

  def test_create_no_id
    mock_document_insert('new_id')
    doc = Document.create('type', 'draft_content', 'published_content', {'meta' => true}, [], Armagh::DocState::WORKING)
    assert_equal('type', doc.type)
    assert_equal('draft_content', doc.draft_content)
    assert_equal('published_content', doc.published_content)
    assert_equal({'meta' => true}, doc.meta)
    assert_equal('new_id', doc.id)
  end

  def test_create_with_id
    mock_document_replace
    doc = Document.create('type', 'draft_content', 'published_content', {'meta' => true}, [], Armagh::DocState::WORKING, 'id')

    assert_equal('type', doc.type)
    assert_equal('draft_content', doc.draft_content)
    assert_equal('published_content', doc.published_content)
    assert_equal({'meta' => true}, doc.meta)
    assert_equal('id', doc.id)
  end

  def test_from_action_document
    id = 'id'
    draft_content = 'blah'
    published_content = 'published_content'
    meta = 'meta'
    doctype = DocTypeState.new('document type', Armagh::DocState::READY)
    new_doc = true
    pending_actions = %w(pend1 pend2)
    action_doc = Armagh::ActionDocument.new(id, draft_content, published_content, meta, doctype, new_doc)
    doc = Document.from_action_document(action_doc, pending_actions)

    assert_equal(id, doc.id)
    assert_equal(draft_content, doc.draft_content)
    assert_equal(published_content, doc.published_content)
    assert_equal(meta, doc.meta)
    assert_equal(doctype.type, doc.type)
    assert_equal(doctype.state, doc.state)
    assert_equal(pending_actions, doc.pending_actions)
  end

  def test_find
    mock_document_find({'_id' => 'docid'})
    doc = Document.find('docid')
    assert_equal('docid', doc.id)
  end

  def test_find_none
    mock_document_find([])
    doc = Document.find('id')
    assert_nil(doc)
  end

  def test_get_for_processing
    mock_document_find_one_and_update({'_id' => 'docid'})
    doc = Document.get_for_processing
    assert_equal('docid', doc.id)
  end

  def test_exists?
    mock_document_find([1])
    assert_true Document.exists?('test', 'testdoc', Armagh::DocState::WORKING)

    mock_document_find([])
    assert_false Document.exists?('test', 'testdoc', Armagh::DocState::WORKING)
  end

  def test_pending_actions
    pending_actions = %w(Action1 Action2 Action3)
    assert_empty(@doc.pending_actions)
    assert_false(@doc.pending_work)

    @doc.add_pending_actions(pending_actions)
    assert_equal(3, @doc.pending_actions.length)
    assert_true(@doc.pending_work)

    pending_actions.each_with_index do |action, idx|
      @doc.remove_pending_action(action)
      assert_equal(3-(1+idx), @doc.pending_actions.length)
    end
    assert_false(@doc.pending_work)

    @doc.add_pending_actions(pending_actions)
    assert_true @doc.pending_work
    @doc.clear_pending_actions
    assert_false @doc.pending_work
    assert_empty @doc.pending_actions
  end

  def test_failed_actions
    assert_empty(@doc.failed_actions)
    assert_false @doc.failed?

    failures = [
        {name: 'failed_action', details: RuntimeError.new('runtime error')},
        {name: 'failed_action2', details: 'string error'},
    ]
    failures.each {|f| @doc.add_failed_action(f[:name], f[:details])}

    assert_equal(2, @doc.failed_actions.length)
    assert_true @doc.failed?

    failures.each do |failure|
      name = failure[:name]
      details = failure[:details]
      assert_true(@doc.failed_actions.has_key? name)
      db_details = @doc.failed_actions[name]
      if details.is_a? Exception
        assert_equal(details.message, db_details['message'])
        assert_equal(details.backtrace, db_details['trace'])
      else
        assert_equal(details, db_details['message'])
      end

      @doc.remove_failed_action(name)
      assert_false(@doc.failed_actions.has_key?(name))
    end

    assert_empty @doc.failed_actions
    assert_false @doc.failed?

    failures.each {|f| @doc.add_failed_action(f[:name], f[:details])}

    assert_true @doc.failed?

    @doc.clear_failed_actions
    assert_false @doc.failed?
    assert_empty @doc.failed_actions

  end

  def test_pending_and_failed
    assert_false @doc.pending_work
    assert_false @doc.failed?

    pending_actions = %w(Action1 Action2 Action3)
    @doc.add_pending_actions pending_actions

    assert_true  @doc.pending_work
    assert_false @doc.failed?

    failures = [
        {name: 'failed_action', details: RuntimeError.new('runtime error')},
        {name: 'failed_action2', details: 'string error'},
    ]
    failures.each {|f| @doc.add_failed_action(f[:name], f[:details])}

    assert_false @doc.pending_work
    assert_true  @doc.failed?

    @doc.clear_failed_actions

    assert_true @doc.pending_work
    assert_false  @doc.failed?

    @doc.clear_pending_actions
    assert_false @doc.pending_work
    assert_false @doc.failed?
  end

  def test_timestamps
    mock_document_replace
    doc = Document.create('type', 'draft_content', 'published_content', {'meta' => true}, [], Armagh::DocState::WORKING, 'id')
    assert_in_delta(Time.now, doc.created_timestamp, 1)
    assert_equal(doc.created_timestamp, doc.updated_timestamp)

    sleep 1
    created_timestamp = doc.created_timestamp
    doc.draft_content = 'New draft content'
    doc.save
    assert_equal(created_timestamp, doc.created_timestamp)
    assert_not_equal(doc.created_timestamp, doc.updated_timestamp)
    assert_true(doc.created_timestamp < doc.updated_timestamp)
  end

  def test_finish_processing
    mock_document_replace
    @doc.finish_processing
    assert_false @doc.locked?
  end

  def test_state
    assert_not_equal(DocState::PUBLISHED, @doc.state)
    @doc.state = DocState::PUBLISHED
    assert_equal(DocState::PUBLISHED, @doc.state)
  end

  def test_invalid_state
    e = assert_raise(Armagh::ActionErrors::StateError){@doc.state = 'this is an invalid state'}
    assert_equal(e.message, "Tried to set state to an unknown state: 'this is an invalid state'.")
  end

  def test_working?
    @doc.state = DocState::PUBLISHED
    assert_false @doc.working?
    @doc.state = DocState::WORKING
    assert_true @doc.working?
  end

  def test_ready?
    @doc.state = DocState::PUBLISHED
    assert_false @doc.ready?
    @doc.state = DocState::READY
    assert_true @doc.ready?
  end

  def test_published?
    @doc.state = DocState::WORKING
    assert_false @doc.published?
    @doc.state = DocState::PUBLISHED
    assert_true @doc.published?
  end

  def test_modify_or_create_new
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    mock_document_find_one_and_update(nil)
    block_executed = false

    Document.modify_or_create(id, type, state) do |doc|
      assert_nil(doc)
      block_executed = true
    end

    assert_true block_executed
  end
  
  def test_modify_or_create_existing
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    mock_document_find_one_and_update({'_id' => id, 'draft_content' => 'doc content', 'published_content' => {}, 'meta' => 'doc meta', 'type' => type, 'state' => state})
    mock_document_replace
    block_executed = false

    Document.modify_or_create(id, type, state) do |doc|
      assert_not_nil doc
      block_executed = true
    end

    assert_true block_executed
  end
  
  def test_modify_or_create_locked
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'E11000 duplicate key error')

    # Have to bail out of the infinite loop somehow
    e = RuntimeError.new
    Utils::ProcessingBackoff.any_instance.expects(:backoff).raises(e)

    block_executed = false

    assert_raise(e) do
      Document.modify_or_create(id, type, state) do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_or_create_unexpected_error
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'Unknown')


    block_executed = false

    assert_raise(Mongo::Error::OperationFailure) do
      Document.modify_or_create(id, type, state) do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_or_create_no_block
    assert_raise(LocalJumpError) do
      Document.modify_or_create('id', 'type', Armagh::DocState::WORKING)
    end
  end

  def test_modify_or_create_bang_new
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    mock_document_find_one_and_update(nil)
    block_executed = false

    result = Document.modify_or_create!(id, type, state) do |doc|
      assert_nil(doc)
      block_executed = true
    end

    assert_true block_executed
    assert_true result
  end

  def test_modify_or_create_bang_existing
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    mock_document_find_one_and_update({'_id' => id, 'draft_content' => 'doc content', 'published_content' => {}, 'meta' => 'doc meta', 'type' => type, 'state' => state})
    mock_document_replace
    block_executed = false

    result = Document.modify_or_create!(id, type, state) do |doc|
      assert_not_nil doc
      block_executed = true
    end

    assert_true block_executed
    assert_true result
  end

  def test_modify_or_create_bang_locked
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'E11000 duplicate key error')
    block_executed = false

    result = Document.modify_or_create!(id, type, state) do |doc|
      assert_not_nil doc
      block_executed = true
    end

    assert_false block_executed
    assert_false result
  end

  def test_modify_or_create_bang_unexpected_error
    id = 'docid'
    type = 'type'
    state = DocState::WORKING
    @documents.expects(:find_one_and_update).raises(Mongo::Error::OperationFailure, 'Unknown')


    block_executed = false

    assert_raise(Mongo::Error::OperationFailure) do
      Document.modify_or_create!(id, type, state) do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_or_create_bang_no_block
    assert_raise(LocalJumpError) do
      Document.modify_or_create!('id', 'type', Armagh::DocState::WORKING)
    end
  end

  def test_to_action_document
    action_doc = @doc.to_action_document
    assert_equal(@doc.draft_content, action_doc.draft_content)
    assert_equal(@doc.published_content, action_doc.published_content)
    assert_equal(@doc.meta, action_doc.meta)
    assert_equal(@doc.state, action_doc.doctype.state)
    assert_equal(@doc.type, action_doc.doctype.type)
  end

  def test_update_from_action_document
    id = 'id'
    draft_content = 'new content'
    published_content = 'old content'
    meta = 'new meta'

    doctype = DocTypeState.new('type', Armagh::DocState::PUBLISHED)
    
    action_document = Armagh::ActionDocument.new(id, draft_content, published_content, meta, doctype)
    
    assert_not_equal(draft_content, @doc.draft_content)
    assert_not_equal(published_content, @doc.published_content)
    assert_not_equal(meta, @doc.meta)
    assert_not_equal(doctype.type, @doc.type)
    assert_not_equal(doctype.state, @doc.state)
    
    @doc.update_from_action_document(action_document)

    assert_equal(draft_content, @doc.draft_content)
    assert_equal(published_content, @doc.published_content)
    assert_equal(meta, @doc.meta)
    assert_equal(doctype.type, @doc.type)
    assert_equal(doctype.state, @doc.state)
  end

  def test_locked?
    assert_false @doc.locked?
    @doc.instance_variable_get(:@db_doc)['locked'] = true
    assert_true @doc.locked?
  end

  def test_delete
    @documents.expects(:delete_one)

    assert_false @doc.deleted?
    @doc.delete
    assert_true @doc.deleted?
  end
end