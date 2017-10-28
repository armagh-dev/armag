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
require_relative '../../../lib/armagh/document/document'
require_relative '../../../lib/armagh/document/trigger_document'

require 'armagh/documents/doc_state'

require 'bson'
require 'time'

require 'test/unit'
require 'mocha/test_unit'

class TestDocument < Test::Unit::TestCase

  def setup
    @documents = mock('documents')
    @internal_id = 'internal_id'
    Armagh::Connection.stubs(:documents).returns(@documents)
    Armagh::Connection.stubs(:all_document_collections).returns([@documents])
    @agent = mock
    @agent.stubs( signature: 'agent-1', running?: true )

    Armagh::Document.default_locking_agent = @agent
    Armagh::TriggerDocument.default_locking_agent = @agent

    mock_insert_one( @internal_id )
    @doc = Armagh::Document.create_one_locked(
        { 'type' => 'testdoc',
          'content' => {'content' => true},
          'raw' => 'raw',
          'metadata' => {'meta' => true},
          'state' => Armagh::Documents::DocState::WORKING,
          'document_id' => 'id',
          'document_timestamp' => Time.new(2016, 1, 1, 0, 0, 0, 0).utc,
          'source' => Armagh::Documents::Source.new( )
        },
        @agent
    )
  end

  def mock_insert_one( id )
    @documents.stubs( insert_one: mock( inserted_ids: [ id ]))
  end

  def test_new
    assert_raise(NoMethodError) { Armagh::Document.new }
    doc = Armagh::Document.send(:new)
    assert_instance_of(Armagh::Document, doc)
  end

  def test_create_with_id

    mock_insert_one( 'id2' )

    doc2 = Armagh::Document.create_one_locked(
        { type: 'testdoc',
          content: {'content' => true},
          raw: 'raw',
          metadata: {'meta' => true},
          state: Armagh::Documents::DocState::WORKING,
          document_id: 'id',
          document_timestamp: Time.new(2016, 1, 1, 0, 0, 0, 0).utc,
          archive_files: ['whatever']
        }
    )

    assert_equal('testdoc', doc2.type)
    assert_equal({'content' => true}, doc2.content)
    assert_equal('raw', doc2.raw)
    assert_equal({'meta' => true}, doc2.metadata)
    assert_equal('id', doc2.document_id)
    assert_equal(['whatever'], doc2.archive_files)
    assert_equal('id2', doc2.internal_id)
  end

  def test_create_trigger_document
    expected_values = { 'type' => 'type',  'state' => 'ready'}

    @documents.expects(:insert_one).with(has_entries(expected_values)).returns( mock( inserted_ids: [ 'internal_id ']))
    Armagh::TriggerDocument.default_locking_agent = @agent
    Armagh::TriggerDocument.create_one_locked(state: Armagh::Documents::DocState::READY, type: 'type', pending_actions: [])
  end

  def test_create_trigger_document_error
    e = RuntimeError.new('error')
    @documents.expects(:insert_one).raises(e)
    assert_raise(e) { Armagh::TriggerDocument.create_one_locked(state: Armagh::Documents::DocState::READY, type: 'type', pending_actions: [])     }
  end

  def test_from_action_document
    id = 'id'
    content = 'blah'
    raw = 'raw'
    metadata = 'draft_meta'
    docspec = Armagh::Documents::DocSpec.new('document type', Armagh::Documents::DocState::READY)
    new_doc = true
    pending_actions = %w(pend1 pend2)
    source = {'some' => 'source'}
    display = 'display'
    title = 'title'
    copyright = 'copyright'
    document_timestamp = Time.at(0)
    action_doc = Armagh::Documents::ActionDocument.new(document_id: id,
                                                       content: content,
                                                       raw: raw,
                                                       metadata: metadata,
                                                       title: title,
                                                       docspec: docspec,
                                                       new: new_doc,
                                                       source: source,
                                                       display: display,
                                                       copyright: copyright,
                                                       document_timestamp: document_timestamp)
    doc = Armagh::Document.from_action_document(action_doc, pending_actions)

    assert_equal(id, doc.document_id)
    assert_equal(content, doc.content)
    assert_equal(raw, doc.raw)
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

  def test_find_many_read_only_by_ts_range
    doc_type = 'reportdoc'
    doc_state = 'ready'
    end_ts = Time.now
    begin_ts = end_ts - 86400
    page_number = 2
    page_size = 50

    report_collection = mock
    Armagh::Connection.stubs( :documents).with(doc_type).returns( report_collection)

    Armagh::Document
        .expects(:find_many_read_only)
        .with(
            { 'document_timestamp' => { '$gte' => begin_ts, '$lte' => end_ts }},
            collection: report_collection,
            sort_rule: { 'document_timestamp' => -1 },
            paging: { page_number: 2, page_size: 50 }
        )
    .returns( [@doc])

    docs = Armagh::Document.find_many_by_ts_range_read_only( doc_type, begin_ts, end_ts, page_number, page_size )
    assert_equal [@doc], docs
  end

  def test_find_one_by_document_id_type_state_locked
    doc_type = 'reportdoc'
    report_collection = mock
    Armagh::Connection.stubs(:documents).with(doc_type).returns( report_collection)
    Armagh::Document
        .expects(:find_one_by_document_id_locked)
        .with( 'id', @agent, collection: report_collection )
        .returns( @doc )

    doc = Armagh::Document.find_one_by_document_id_type_state_locked( 'id', doc_type, 'published' )
    assert_equal 'id', doc.document_id
  end

  def test_find_one_by_document_id_type_state_read_only
    doc_type = 'reportdoc'
    report_collection = mock
    Armagh::Connection.stubs(:documents).with(doc_type).returns( report_collection)
    Armagh::Document
        .expects(:find_one_by_document_id_read_only)
        .with( 'id', collection: report_collection )
        .returns( @doc )

    doc = Armagh::Document.find_one_by_document_id_type_state_read_only( 'id', doc_type, 'published' )
    assert_equal 'id', doc.document_id
  end

  def test_get_one_for_processing_locked
    Armagh::Document
        .expects(:find_one_locked)
        .with({'pending_work'=>true}, @agent, collection: @documents, oldest: true, lock_wait_duration: 0 )
        .returns( @doc)
    @doc.expects(:save)
    res = Armagh::Document.get_one_for_processing_locked do |doc|
      assert_equal('id', doc.document_id)
    end
    assert_true res
  end

  def test_get_for_processing_error
    e = Mongo::Error.new('error')
    @documents.expects(:find_one_and_update).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) { Armagh::Document.get_one_for_processing_locked }
  end

  def test_exists?
    Armagh::Document.expects( :find_one_read_only ).returns( @doc )
    assert_true Armagh::Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING)

    Armagh::Document.expects( :find_one_read_only ).returns( nil )
    assert_false Armagh::Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING)
  end

  def test_exists_error
    e = Mongo::Error.new('error')
    @documents.expects(:find).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) { Armagh::Document.exists?('test', 'testdoc', Armagh::Documents::DocState::WORKING) }
  end

  def test_pending_actions
    pending_actions = %w(Action1 Action2 Action3)
    assert_empty(@doc.pending_actions)
    assert_false(@doc.pending_work?)

    @doc.add_items_to_pending_actions(pending_actions)
    assert_equal(3, @doc.pending_actions.length)
    assert_true(@doc.pending_work?)

    pending_actions.each_with_index do |action, idx|
      @doc.remove_item_from_pending_actions(action)
      assert_equal(3-(1+idx), @doc.pending_actions.length)
    end
    assert_false(@doc.pending_work?)

    @doc.add_items_to_pending_actions(pending_actions)
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
    failures.each { |f| @doc.add_error_to_dev_errors(f[:name], f[:details]) }

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

      assert_kind_of(Time, db_details['timestamp'])

      @doc.remove_action_from_dev_errors(name)
      assert_false(@doc.dev_errors.has_key?(name))
    end

    assert_empty @doc.dev_errors
    assert_false @doc.error?

    failures.each { |f| @doc.add_error_to_dev_errors(f[:name], f[:details]) }

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
    failures.each { |f| @doc.add_error_to_ops_errors(f[:name], f[:details]) }

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

      assert_kind_of(Time, db_details['timestamp'])

      @doc.remove_action_from_ops_errors(name)
      assert_false(@doc.ops_errors.has_key?(name))
    end

    assert_empty @doc.ops_errors
    assert_false @doc.error?

    failures.each { |f| @doc.add_error_to_ops_errors(f[:name], f[:details]) }

    assert_true @doc.error?

    @doc.clear_ops_errors
    assert_false @doc.error?
    assert_empty @doc.ops_errors
  end

  def test_pending_and_failed
    assert_false @doc.pending_work?
    assert_false @doc.error?

    pending_actions = %w(Action1 Action2 Action3)
    @doc.add_items_to_pending_actions pending_actions

    assert_true @doc.pending_work?
    assert_false @doc.error?

    failures = [
      {name: 'failed_action', details: RuntimeError.new('runtime error')},
      {name: 'failed_action2', details: 'string error'},
    ]
    failures.each { |f| @doc.add_error_to_dev_errors(f[:name], f[:details]) }

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
    assert_raises Armagh::BaseDocument::NoChangesAllowedError.new( "only the database can set internal_id" ) do
      @doc.internal_id = internal
    end
  end

  def test_collection_task_ids
    assert_empty @doc.collection_task_ids
    @doc.add_item_to_collection_task_ids 1
    @doc.add_item_to_collection_task_ids 2
    assert_equal([1, 2], @doc.collection_task_ids)
  end

  def test_state
    assert_not_equal(Armagh::Documents::DocState::PUBLISHED, @doc.state)
    @doc.state = Armagh::Documents::DocState::PUBLISHED
    assert_equal(Armagh::Documents::DocState::PUBLISHED, @doc.state)
  end

  def test_invalid_state
    e = assert_raise(Armagh::Documents::Errors::DocStateError) { @doc.state = 'this is an invalid state' }
    assert_equal(e.message, "Tried to set state to an unknown state: 'this is an invalid state'.")
  end

  def test_working?
    @doc.state = Armagh::Documents::DocState::PUBLISHED
    assert_false @doc.working?
    @doc.state = Armagh::Documents::DocState::WORKING
    assert_true @doc.working?
  end

  def test_ready?
    @doc.state = Armagh::Documents::DocState::PUBLISHED
    assert_false @doc.ready?
    @doc.state = Armagh::Documents::DocState::READY
    assert_true @doc.ready?
  end

  def test_published?
    @doc.state = Armagh::Documents::DocState::WORKING
    assert_false @doc.published?
    @doc.state = Armagh::Documents::DocState::PUBLISHED
    assert_true @doc.published?
  end

  def test_get_published_copy_read_only
    mock_insert_one( 4 )
    pdoc = Armagh::Document.create_one_locked(
        { 'type' => 'testdoc',
          'content' => {'content' => true},
          'raw' => 'raw',
          'metadata' => {'meta' => true},
          'state' => Armagh::Documents::DocState::PUBLISHED,
          'document_id' => 'other',
          'document_timestamp' => Time.new(2016, 1, 1, 0, 0, 0, 0).utc
        },
        @agent
    )
    Armagh::Document.expects(:find_one_read_only).returns(pdoc)
    found = @doc.get_published_copy_read_only
    assert_equal('other', found.document_id)
  end

  def test_to_draft_action_document
    action_doc = @doc.to_action_document
    assert_equal(@doc.content, action_doc.content)
    assert_equal(@doc.raw, action_doc.raw)
    assert_equal(@doc.metadata, action_doc.metadata)
    assert_equal(@doc.state, action_doc.docspec.state)
    assert_equal(@doc.type, action_doc.docspec.type)
    assert_equal(@doc.source, action_doc.source.to_hash.delete_if { |k, v| v.nil? })
  end

  def test_to_published_document
    pub_doc = @doc.to_published_document
    assert_equal(@doc.content, pub_doc.content)
    assert_equal(@doc.raw, pub_doc.raw)
    assert_equal(@doc.metadata, pub_doc.metadata)
    assert_equal(@doc.state, pub_doc.docspec.state)
    assert_equal(@doc.type, pub_doc.docspec.type)
    assert_equal(@doc.source, pub_doc.source.to_hash.dup.delete_if { |k, v| v.nil? })
  end

  def test_update_from_draft_action_document
    id = 'id'
    content = 'new content'
    raw = 'new raw'
    metadata = 'new meta'
    source = {'some' => 'source'}
    title = 'title'
    copyright = 'copyright'
    document_timestamp = Time.at(13249)

    docspec = Armagh::Documents::DocSpec.new('type', Armagh::Documents::DocState::PUBLISHED)

    action_document = Armagh::Documents::ActionDocument.new(document_id: id,
                                                            content: content,
                                                            raw: raw,
                                                            metadata: metadata,
                                                            docspec: docspec,
                                                            source: source,
                                                            title: title,
                                                            copyright: copyright,
                                                            document_timestamp: document_timestamp)

    assert_not_equal(content, @doc.content)
    assert_not_equal(raw, @doc.raw)
    assert_not_equal(metadata, @doc.metadata)
    assert_not_equal(docspec.type, @doc.type)
    assert_not_equal(docspec.state, @doc.state)
    assert_not_equal(title, @doc.title)
    assert_not_equal(copyright, @doc.copyright)
    assert_not_equal(document_timestamp, @doc.document_timestamp)

    @doc.update_from_draft_action_document(action_document)

    assert_equal(content, @doc.content)
    assert_equal(raw, @doc.raw)
    assert_equal(metadata, @doc.metadata)
    assert_equal(docspec.type, @doc.type)
    assert_equal(docspec.state, @doc.state)
    assert_equal(title, @doc.title)
    assert_equal(copyright, @doc.copyright)
    assert_equal(document_timestamp, @doc.document_timestamp)
  end


  def assert_changes_collection_on_save( target_connection_method, connection_arg, mark_method, mark_variable )
    if target_connection_method
      new_collection = mock
      if connection_arg
        Armagh::Connection.expects( target_connection_method ).with(connection_arg).returns(new_collection)
      else
        Armagh::Connection.expects( target_connection_method ).returns( new_collection )
      end
      new_collection.expects(:insert_one).once.returns( mock( inserted_ids: ['internal_id']))
    end
    @documents.expects(:delete_one).returns( mock( deleted_count: 1 ))

    if mark_variable && mark_method
      assert_false @doc.instance_variable_get(mark_variable)
      @doc.send(mark_method)
      assert_true @doc.instance_variable_get(mark_variable)
    end

    @doc.save
    assert_false @doc.instance_variable_get(mark_variable) if mark_variable && mark_method
  end

  def test_archive_save
    assert_changes_collection_on_save( :collection_history, nil, :mark_collection_history, :@pending_collection_history )
  end

  def test_delete_save
    assert_changes_collection_on_save( nil, nil, :mark_delete, :@pending_delete )
  end

  def test_publish_save
    assert_changes_collection_on_save( :documents, 'testdoc', :mark_publish, :@pending_publish )
  end

  def test_abort_save
    assert_changes_collection_on_save( nil, nil, :mark_abort, :@abort )
  end

  def test_failed_action_save
    @doc.add_error_to_dev_errors( 'test_action', 'Failure Details' )
    assert_changes_collection_on_save( :failures, nil, nil, nil )
  end

  def test_abort_save_published
    replace_results = mock( modified_count: 1 )
    @documents.expects(:replace_one).returns( replace_results )
    @doc.state = Armagh::Documents::DocState::PUBLISHED
    @doc.mark_abort
    @doc.save
  end

  def test_too_large
    @documents.expects(:insert_one).raises(Mongo::Error::MaxBSONSize)

    error = assert_raise(Armagh::Connection::DocumentSizeError) do
      Armagh::Document.create_one_locked(type: 'testdoc',
                      content: {'content' => true},
                      metadata: {'meta' => true},
                      state: Armagh::Documents::DocState::PUBLISHED,
                      document_id: 'id',
                      document_timestamp: Time.now)
    end

    assert_equal "Document id is too large.  Consider using a divider or splitter to break up the document.", error.message
  end

  def test_duplicate
    @documents.expects(:insert_one).raises(Mongo::Error::OperationFailure.new('E11000 Some context'))

    error = assert_raise(Armagh::Connection::DocumentUniquenessError) do
      Armagh::Document.create_one_locked(
          { 'type' => 'testdoc',
            'content' => {'content' => true},
            'metadata' => {'meta' => true},
            'state' => Armagh::Documents::DocState::PUBLISHED,
            'document_id' => 'id',
            'document_timestamp' => Time.now } )
    end

    assert_equal 'Unable to create Document id.  This document already exists.', error.message
  end

  def test_unknown_operation_error
    error = Mongo::Error::OperationFailure.new('Something')
    @documents.expects(:insert_one).raises(error)

    assert_raise(Armagh::Connection::ConnectionError.new('An unexpected connection error occurred from Document id: Something.')) do
      Armagh::Document.create_one_locked(type: 'testdoc',
                      content: {'content' => true},
                      metadata: {'meta' => true},
                      state: Armagh::Documents::DocState::PUBLISHED,
                      document_id: 'id',
                      document_timestamp: Time.now)
    end
  end

  def test_class_version
    version = '12345abcdefh'
    Armagh::Document.version['armagh'] = version
    assert_equal({'armagh' => version}, Armagh::Document.version)
    Armagh::Document.version.delete 'armagh'
  end

  def test_version
    @documents.expects(:replace_one).returns( mock( modified_count: 1))
    version = '12345abcdefh'
    Armagh::Document.version['armagh'] = version
    @doc.save
    assert_equal({'armagh' => version}, @doc.version)
    Armagh::Document.version.delete 'armagh'
  end

  def test_clear_errors
    @doc.add_error_to_dev_errors('test', 'test')
    @doc.add_error_to_ops_errors('test', 'test')
    assert_false @doc.dev_errors.empty?
    assert_false @doc.ops_errors.empty?
    @doc.clear_errors
    assert_true @doc.dev_errors.empty?
    assert_true @doc.ops_errors.empty?
  end


  def test_find_all_failures_read_only
    failures = mock('failures')
    failures.stubs(:find => [{'document_id' => 'fail id'}])
    Armagh::Connection.stubs(:failures).returns(failures)

    found_failures = Armagh::Document.find_all_failures_read_only
    assert_equal 1, found_failures.length
    assert_kind_of Armagh::Document, found_failures.first
    assert_equal 'fail id', found_failures.first.document_id
  end

  def test_to_json
    expected = {
      type: @doc.type,
      content: @doc.content,
      raw: BSON::Binary.new(@doc.raw),
      metadata: @doc.metadata,
      state: @doc.state,
      document_id: @doc.document_id,
      document_timestamp: @doc.document_timestamp,
      source: @doc.source&.to_hash,
      _locked: @doc.instance_variable_get(:@image)[ '_locked'],
      pending_actions: @doc.pending_actions,
      dev_errors: @doc.dev_errors,
      ops_errors: @doc.ops_errors,
      version: @doc.version,
      collection_task_ids: @doc.collection_task_ids,
      archive_files: @doc.archive_files,
      updated_timestamp: @doc.updated_timestamp,
      created_timestamp: @doc.created_timestamp,
      internal_id: @doc.internal_id
    }.to_json
    assert_equal(expected, @doc.to_json)
  end

  def setup_count_incomplete_tests

    docs_type1 = mock
    docs_type2 = mock
    failures = mock
    %w{ docs_type1 docs_type2 }.each do |coll_mock|
      Armagh::Connection.stubs( :documents ).with( coll_mock ).returns( eval(coll_mock))
      eval(coll_mock).stubs( :name ).returns( coll_mock)
      eval(coll_mock)
          .stubs( :aggregate )
          .with( [
                     { '$match'=>{ 'pending_work' => true }},
                     { '$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}
                 ])
          .returns( [{ '_id' => { 'type' => coll_mock, 'state' => 'published' }, 'count' => 4 }] )
    end
    @documents.stubs( :name ).returns( 'documents' )
    @documents
        .stubs( :aggregate )
        .with( [{'$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}])
        .returns( [{ '_id' => { 'type' => 'pre_docs_type1', 'state' => 'ready' }, 'count' => 3 },
                   { '_id' => { 'type' => 'pre_docs_type2', 'state' => 'ready' }, 'count' => 6 }] )
    Armagh::Connection.stubs( :failures ).returns( failures )
    failures.stubs( :name ).returns( 'failures' )
    failures
        .stubs( :aggregate )
        .with( [{'$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}])
        .returns( [{ '_id' => { 'type' => 'failures', 'state' => 'ready' }, 'count' => 3 }] )
    Armagh::Connection.stubs(:all_document_collections).returns( [ @documents, docs_type1, docs_type2])
    Armagh::Connection.stubs( :published_collection?).with( @documents ).returns(false)
    Armagh::Connection.stubs( :published_collection?).with( docs_type1 ).returns(true)
    Armagh::Connection.stubs( :published_collection?).with( docs_type2 ).returns(true)

  end

  def test_count_incomplete_all
    setup_count_incomplete_tests

    counts = nil
    assert_nothing_raised do
      counts = Armagh::Document.count_incomplete_by_doctype
    end
    expected_counts =  {
        'documents' => { 'pre_docs_type1:ready'=>3, 'pre_docs_type2:ready'=>6 },
        'failures'  => {'failures:ready'=>3},
        'docs_type1' => {'docs_type1:published'=>4},
        'docs_type2'=>{'docs_type2:published'=>4} }
    assert_equal expected_counts, counts
  end

  def test_count_incomplete_selected
    setup_count_incomplete_tests

    counts = nil
    assert_nothing_raised do
      counts = Armagh::Document.count_incomplete_by_doctype( ['docs_type1'])
    end
    expected_counts =  {
        'documents' => { 'pre_docs_type1:ready'=>3, 'pre_docs_type2:ready'=>6 },
        'failures'  => {'failures:ready'=>3},
        'docs_type1' => {'docs_type1:published'=>4} }
    assert_equal expected_counts, counts

  end
end
