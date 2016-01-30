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
require_relative '../../lib/document/document'

require 'armagh/doc_state'

require 'test/unit'
require 'mocha/test_unit'

class TestDocument < Test::Unit::TestCase

  include Armagh

  def setup
    @documents = mock
    mock_document_insert('id')
    Armagh::Connection.stubs(:documents).returns(@documents)
    @doc = Document.create('testdoc', 'content', 'meta', [], Armagh::DocState::PENDING)
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
    doc = Document.create('type', 'content', 'meta', [], Armagh::DocState::PENDING)
    assert_equal('type', doc.type)
    assert_equal('content', doc.content)
    assert_equal('meta', doc.meta)
    assert_equal('new_id', doc.id)
  end

  def test_create_with_id
    mock_document_replace
    doc = Document.create('type', 'content', 'meta', [], Armagh::DocState::PENDING, 'id')

    assert_equal('type', doc.type)
    assert_equal('content', doc.content)
    assert_equal('meta', doc.meta)
    assert_equal('id', doc.id)
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

  def test_md5
    content = 'new content for md5 test'
    md5 = Digest::MD5.hexdigest(content)

    assert_not_equal(md5, @doc.md5)
    @doc.content = content
    assert_equal(md5, @doc.md5)
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
  end

  def test_failed_actions
    assert_empty(@doc.failed_actions)

    failures = [
        {name: 'failed_action', details: RuntimeError.new('runtime error')},
        {name: 'failed_action2', details: 'string error'},
    ]
    failures.each {|f| @doc.add_failed_action(f[:name], f[:details])}

    assert_equal(2, @doc.failed_actions.length)

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

  end

  def test_timestamps
    mock_document_replace
    doc = Document.create('type', 'content', 'meta', [], Armagh::DocState::PENDING, 'id')
    assert_in_delta(Time.now, doc.created_timestamp, 1)
    assert_equal(doc.created_timestamp, doc.updated_timestamp)

    sleep 1
    created_timestamp = doc.created_timestamp
    doc.content = 'New content'
    doc.save
    assert_equal(created_timestamp, doc.created_timestamp)
    assert_not_equal(doc.created_timestamp, doc.updated_timestamp)
    assert_true(doc.created_timestamp < doc.updated_timestamp)
  end

  def test_finish_processing
    mock_document_replace
    @doc.finish_processing
    assert_false(@doc.instance_variable_get(:@db_doc)['locked'])
  end

  def test_state
    assert_not_equal(DocState::CLOSED, @doc.state)
    @doc.state = DocState::CLOSED
    assert_equal(DocState::CLOSED, @doc.state)
  end

  def test_invalid_state
    e = assert_raise(RuntimeError) do
      @doc.state = 'this is an invalid state'
    end

    assert_equal(e.message, "Tried to set state to an unknown state: 'this is an invalid state'.")

  end

  def test_pending?
    @doc.state = DocState::CLOSED
    assert_false @doc.pending?
    @doc.state = DocState::PENDING
    assert_true @doc.pending?
  end

  def test_published?
    @doc.state = DocState::CLOSED
    assert_false @doc.published?
    @doc.state = DocState::PUBLISHED
    assert_true @doc.published?
  end

  def test_closed?
    @doc.state = DocState::PUBLISHED
    assert_false @doc.closed?
    @doc.state = DocState::CLOSED
    assert_true @doc.closed?
  end

  def test_modify
    id = 'docid'
    mock_document_find_one_and_update({'_id' => id, 'content' => 'doc content', 'meta' => 'doc meta'})
    mock_document_replace
    block_executed = false

    result = Document.modify(id) do |doc|
      assert_equal(id, doc.id)
      block_executed = true
    end

    assert_true block_executed
    assert_true result
  end
  
  def test_modify_none
    id = 'docid'
    mock_document_find_one_and_update(nil)
    mock_document_find([])
    mock_document_replace

    result = Document.modify(id) do |doc|
      # Should never execute this
      fail
    end

    assert_false result
  end
  
  def test_modify_locked
    id = 'docid'
    mock_document_find_one_and_update(nil)
    mock_document_find({'_id' => id, 'content' => 'doc content', 'meta' => 'doc meta'})
    mock_document_replace

    e = RuntimeError.new

    # Have to bail out of the infinite loop somehow
    Utils::ProcessingBackoff.any_instance.expects(:backoff).raises(e)

    block_executed = false

    assert_raise(e) do
      Document.modify(id) do |doc|
        block_executed = true
      end
    end

    assert_false block_executed
  end

  def test_modify_no_block
    assert_raise(LocalJumpError) do
      Document.modify('id')
    end
  end

  def test_modify_bang
    id = 'docid'
    mock_document_find_one_and_update({'_id' => id, 'content' => 'doc content', 'meta' => 'doc meta'})
    mock_document_replace
    block_executed = false

    result = Document.modify!(id) do |doc|
      assert_equal(id, doc.id)
      block_executed = true
    end

    assert_true block_executed
    assert_true result
  end
  
  def test_modify_bang_none
    id = 'docid'
    mock_document_find_one_and_update(nil)
    mock_document_replace

    result = Document.modify!(id) do |doc|
      # Should never execute this
      fail
    end

    assert_false result
  end
  
  def test_modify_bang_not_blocked_by_lock
    id = 'docid'
    mock_document_find_one_and_update(nil)
    mock_document_replace

    block_executed = false

    result = Document.modify!(id) do |doc|
      block_executed = true
    end

    assert_false block_executed
    assert_false result
  end

  def test_modify_bang_no_block
    assert_raise(LocalJumpError) do
      Document.modify!('id')
    end
  end

  def test_to_action_document
    action_doc = @doc.to_action_document
    assert_equal(@doc.content, action_doc.content)
    assert_equal(@doc.meta, action_doc.meta)
    assert_equal(@doc.state, action_doc.state)
  end

  def test_update_from_action_document
    content = 'new content'
    meta = 'new meta'
    state = Armagh::DocState::PUBLISHED
    
    action_document = Armagh::ActionDocument.new(content, meta, state)
    
    assert_not_equal(content, @doc.content)
    assert_not_equal(meta, @doc.meta)
    assert_not_equal(state, @doc.state)
    
    @doc.update_from_action_document(action_document)

    assert_equal(content, @doc.content)
    assert_equal(meta, @doc.meta)
    assert_equal(state, @doc.state)
  end

end