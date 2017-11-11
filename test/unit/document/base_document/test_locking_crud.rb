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

require_relative '../../../../lib/armagh/document/base_document/document'
require_relative '../../../../lib/armagh/document/base_document/locking_crud'
require_relative '../../../../lib/armagh/connection/mongo_error_handler'
require 'test/unit'
require 'mocha/test_unit'

class CollectionLA; end
class CollectionFailedLA; end

LOCK_HOLD_DURATION = 10
class DocumentLA < Armagh::BaseDocument::Document
  include Armagh::BaseDocument::LockingCRUD
  def self.default_collection; CollectionLA; end
  def self.default_lock_hold_duration; LOCK_HOLD_DURATION; end
  def self.default_lock_wait_duration; 15; end
  delegated_attr_accessor :name
  delegated_attr_accessor :message
  delegated_attr_accessor :color
end

class TestBaseDocumentLockingCRUD < Test::Unit::TestCase

  def setup
    @caller = mock
    @caller.expects( :signature).at_least(0).returns('iami' )
    @caller.expects(:running?).at_least(0).returns(true)
  end

  def shutdown
    Object.send(:remove_const, :CollectionLA)
    Object.send(:remove_const, :DocumentLA)
  end

  def has_valid_unlock_qualifier( query_qualifier, orig_qual, _locker_sig )
    original_qual, unlocked_clause = query_qualifier[ '$and']
    original_qual == orig_qual && unlocked_clause == { '_locked' => false }
  end

  def has_valid_unlock_or_my_qualifier( query_qualifier, orig_qual, locker_sig )
    original_qual, unlocked_or_my_clause = query_qualifier[ '$and']
    or_clause = unlocked_or_my_clause[ '$or' ]
    original_qual == orig_qual && or_clause.first(2) == [{ '_locked' => false}, {'_locked.by' => locker_sig }]
  end

  def parse_locking_set( set )
    s = set.deep_copy
    locked = s['$set'].delete '_locked'
    { by: locked[ 'by'], until: locked['until'], orig_set: s }
  end

  def has_valid_locking_set( query_set, locker_sig, orig_set )
    pset = parse_locking_set( query_set )

    pset[ :by ] == locker_sig &&
        pset[ :orig_set ]['$set'] == orig_set &&
        pset[ :until ].is_a?(Time)
  end

  def has_valid_lock_params( query_qualifier, query_set, locker_sig, orig_qual, orig_set )
    has_valid_unlock_qualifier( query_qualifier, orig_qual, locker_sig) &&
    has_valid_locking_set( query_set, locker_sig, orig_set )
  end

  def has_locked_until( h )
    h.keys.include? '_locked.until'
  end

  def is_locked( doc, by )
    locked = doc.send(:instance_variable_get, '@image' )['_locked']
    locked&.[]('by') == by && locked&.[]('until')&.>( Time.now)
  end

  def test_create_one
    assert_raises NoMethodError.new("Create_one not available in locking documents.  Use create_one_locked or create_one_unlocked.") do
      DocumentLA.create_one( {})
    end
  end

  def test_create_one_locked
    values = { 'name' => 'inigo montoya' }

    insert_report=mock( inserted_ids: [1])
    CollectionLA.expects( :insert_one ).with( has_entries(values) ){ |hash|
      hash['_locked']['by'] == 'iami' &&
          hash['_locked']['until'].is_a?( Time)
    }.returns( insert_report )
    doc = DocumentLA.create_one_locked( values, @caller )
    assert_equal 'inigo montoya', doc.name
    assert_equal 1, doc.internal_id
  end

  def test_create_one_locked_mongo_error
    values = { 'name' => 'inigo montoya' }

    CollectionLA.expects( :insert_one ).raises( Mongo::Error::MaxBSONSize)
    assert_raises Armagh::Connection::DocumentSizeError do
      doc = DocumentLA.create_one_locked( values, @caller )
    end
  end

  def test_find_one
    assert_raises NoMethodError.new( "Find_one not available in locking documents.  Use find_one_locked or find_one_read_only.") do
      DocumentLA.find_one( {} )
    end
  end

  def test_find_one_locked
    qualifier = { '_id' => 2 }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_locked' => { 'by' => 'iami', 'until' => Time.now + 10} })
    CollectionLA.expects(:find_one_and_update).with(){ |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
      options == {:return_document => :after }
    }.returns( expected_doc_image )
    doc = DocumentLA.find_one_locked( qualifier, @caller )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert is_locked( doc, 'iami' ), "not locked"
    assert_false doc.read_only?
  end

  def test_find_one_read_only
    qualifier = { '_id' => 2 }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', 'document_id' => 123 })
    find_response = mock
    find_response.expects( :limit ).with(1).returns [expected_doc_image ]
    CollectionLA.expects(:find).with(qualifier).returns( find_response )
    doc = DocumentLA.find_one_read_only( qualifier )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert_false is_locked( doc, 'iami' )
    assert doc.read_only?
    assert_raises Armagh::BaseDocument::ReadOnlyError.new( "DocumentLA 123 is read-only and cannot be saved") do
      doc.save
    end
  end

  def test_find_one_locked_not_found
    qualifier = { '_id' => 2 }
    CollectionLA.expects(:find_one_and_update).with() { |qualifier, set, options|
        has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
        options == {:return_document => :after }
    }.returns( nil )
    find_return = mock( limit: [] )
    CollectionLA.expects(:find).with( qualifier ).returns(find_return)
    doc = DocumentLA.find_one_locked( qualifier, @caller )
    assert_nil doc
  end

  def test_find_one_locked_mongo_error
    qualifier = { '_id' => 2 }
    CollectionLA.expects(:find_one_and_update).with() { |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
      options == {:return_document => :after }
    }.raises( Mongo::Error.new( 'oops' ) )
    assert_raises Armagh::Connection::ConnectionError.new('An unexpected connection error occurred from Document: oops.') do
      DocumentLA.find_one_locked( qualifier, @caller )
    end
  end

  def test_find_one_read_only_not_found
    qualifier = { '_id' => 2 }
    find_response = mock
    find_response.expects( :limit ).with(1).returns [ ]
    CollectionLA.expects(:find).with(qualifier).returns( find_response )
    doc = DocumentLA.find_one_read_only( qualifier )
    assert_nil doc
  end

  def test_find_one_read_only_mongo_error
    qualifier = { '_id' => 2 }
    CollectionLA.expects(:find).raises( Mongo::Error.new( 'oops'))
    assert_raises Armagh::Connection::ConnectionError.new("An unexpected connection error occurred from Document: oops.") do
      DocumentLA.find_one_read_only( qualifier )
    end
  end

  def test_find
    assert_raises NoMethodError.new( "Find not available in locking documents.  Use find_many_read_only.") do
      DocumentLA.find( {} )
    end
  end

  def test_find_many_read_only_found
    qualifier = { 'color' => 'blue' }
    expected_doc_images = 5.times.collect{ |i| qualifier.merge( 'document_id' => i )}
    CollectionLA.expects(:find).with(qualifier).returns( expected_doc_images )
    docs = DocumentLA.find_many_read_only( qualifier )
    assert_equal 5, docs.count
    assert_equal [0,1,2,3,4], docs.collect( &:document_id)
    assert_false is_locked( docs[4], 'iami' )
    assert docs[3].read_only?
    assert_raises Armagh::BaseDocument::ReadOnlyError.new( "DocumentLA 0 is read-only and cannot be saved") do
      docs[0].save
    end
  end

  def test_find_many_read_only_not_found
    qualifier = { 'color' => 'blue' }
    CollectionLA.expects(:find).with(qualifier).returns( [] )
    docs = DocumentLA.find_many_read_only( qualifier )
    assert_empty docs
  end

  def test_find_many_read_only_mongo_error
    qualifier = { 'color' => 'blue' }
    CollectionLA.expects(:find).raises( Mongo::Error.new( 'oops'))
    assert_raises Armagh::Connection::ConnectionError.new("An unexpected connection error occurred from Document: oops.") do
      DocumentLA.find_many_read_only( qualifier )
    end
  end

  def test_find_or_create_one_locked_found
    qualifier = { '_id' => 2 }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_locked' => { 'by' => 'iami', 'until' => Time.now + 10} })
    CollectionLA.expects(:find_one_and_update).with(){ |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
          options == {:return_document => :after }
    }.returns( expected_doc_image )
    doc = DocumentLA.find_or_create_one_locked( qualifier, {}, @caller)
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert is_locked( doc, 'iami' ), "not locked"
  end

  def test_find_or_create_one_locked_created
    values = { 'name' => 'inigo montoya' }

    CollectionLA.expects(:find_one_and_update).once.with() { |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, values, {}) &&
      options == {:return_document => :after }
    }.returns( nil )

    find_return = mock( limit: [] )
    CollectionLA.expects(:find).with(values).returns( find_return)

    insert_report=mock
    insert_report.expects(:inserted_ids).returns([ 1 ])
    CollectionLA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )

    doc = DocumentLA.find_or_create_one_locked( values, values, @caller )
    assert_equal 'inigo montoya', doc.name
    assert_equal 1, doc.internal_id
    assert_false doc.read_only?
    assert is_locked( doc, 'iami')
  end

  def test_find_one_by_internal_id_locked
    internal_id = 2
    qualifier = { '_id' => 2 }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_locked' => { 'by' => 'iami', 'until' => Time.now + 10} })
    CollectionLA.expects(:find_one_and_update).with(){ |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
          options == {:return_document => :after }
    }.returns( expected_doc_image )
    doc = DocumentLA.find_one_by_internal_id_locked( internal_id, @caller )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert is_locked( doc, 'iami' ), "not locked"
  end

  def test_get_locked
    internal_id = 2
    qualifier = { '_id' => 2 }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_locked' => { 'by' => 'iami', 'until' => Time.now + 10} })
    CollectionLA.expects(:find_one_and_update).with(){ |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, { '_id' => 2 }, {}) &&
          options == {:return_document => :after }
    }.returns( expected_doc_image )
    doc = DocumentLA.get_locked( internal_id, @caller )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert is_locked( doc, 'iami' ), "not locked"
    assert_false doc.read_only?
  end

  def test_get_read_only
    internal_id = 2
    qualifier = { '_id' => internal_id }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', 'document_id' => 123 })
    find_response = mock
    find_response.expects( :limit ).with(1).returns [expected_doc_image ]
    CollectionLA.expects(:find).with(qualifier).returns( find_response )
    doc = DocumentLA.get_read_only( internal_id )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert_false is_locked( doc, 'iami' )
    assert doc.read_only?
    assert_raises Armagh::BaseDocument::ReadOnlyError.new( "DocumentLA 123 is read-only and cannot be saved") do
      doc.save
    end
  end

  def test_find_one_by_document_id
    assert_raises NoMethodError.new( "Find_one_by_document_id not available in locking documents.  Use find_one_by_document_id_locked or find_one_by_document_id_read_only.") do
      DocumentLA.find_one_by_document_id( {} )
    end
  end

  def test_find_one_by_document_id_locked
    document_id = 2
    qualifier = { 'document_id' => document_id }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_id' => 2, '_locked' => { 'by' => 'iami', 'until' => Time.now + 10} })
    CollectionLA.expects(:find_one_and_update).with(){ |qualifier, set, options|
      has_valid_lock_params( qualifier, set, @caller.signature, {'document_id' => document_id }, {}) &&
          options == {:return_document => :after }
    }.returns( expected_doc_image )
    doc = DocumentLA.find_one_by_document_id_locked( document_id, @caller )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert is_locked( doc, 'iami' ), "not locked"
  end

  def test_find_one_by_document_id_read_only
    document_id = 'fred'
    qualifier = { 'document_id' => document_id }
    expected_doc_image = qualifier.merge( { 'message' => 'you keeled my father', '_id' => 2 })
    find_response = mock
    find_response.expects( :limit ).with(1).returns [expected_doc_image ]
    CollectionLA.expects(:find).with(qualifier).returns( find_response )
    doc = DocumentLA.find_one_by_document_id_read_only( document_id )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
    assert_false is_locked( doc, 'iami' )
    assert doc.read_only?
    assert_raises Armagh::BaseDocument::ReadOnlyError.new( "DocumentLA fred is read-only and cannot be saved") do
      doc.save
    end
  end

  def test_create_change_then_save
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_update = 2

    changed_values = { 'message' => 'prepare to die' }
    insert_report=mock(inserted_ids: [ internal_id ])
    CollectionLA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentLA.create_one_locked( values, @caller )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_update

    doc.message = "prepare to die"

    original_updated_timestamp = doc.updated_timestamp

    replace_result = mock( modified_count: 1 )
    CollectionLA.expects(:replace_one).with(){ |qualifier, new_doc|
      has_valid_unlock_or_my_qualifier( qualifier, {'_id' => 3}, @caller.signature )
    }.returns( replace_result )

    doc.save( true, @caller)
    assert_equal 'prepare to die', doc.message
    assert_in_delta sleep_between_create_and_update, ( doc.updated_timestamp - original_updated_timestamp  ), 0.5
  end

  def test_with_new_or_existing_locked_document
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }

    changed_values = { 'message' => 'prepare to die' }

    CollectionLA.expects(:find_one_and_update ).returns(nil)
    CollectionLA.expects(:find).returns( mock( limit: [] ))
    insert_report=mock(inserted_ids: [ internal_id ])
    CollectionLA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )

    replace_result = mock( modified_count: 1 )
    CollectionLA.expects(:replace_one).with(){ |qualifier, new_doc|
      has_valid_unlock_or_my_qualifier( qualifier, {'_id' => 3}, @caller.signature )
    }.returns( replace_result )

    DocumentLA.with_new_or_existing_locked_document( qualifier, values, @caller ) do |doc|
      assert_equal 'inigo montoya', doc.name
      assert_equal internal_id, doc.internal_id
      assert_false doc.read_only?
      assert 'iami', doc.locked_by

      doc.message = "prepare to die"
    end

  end

  def test_create_change_collection_then_save
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_update = 2

    insert_report=mock(inserted_ids:[ internal_id ])
    CollectionLA.expects( :insert_one ).with( has_entries(values )).returns( insert_report )
    doc = DocumentLA.create_one_locked( values, @caller )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_update

    doc.message = "prepare to die"
    changed_values = { 'message' => 'prepare to die' }
    new_values = values.merge( changed_values )
    original_updated_timestamp = doc.updated_timestamp
    insert_report = mock( inserted_ids: [3])
    CollectionFailedLA.expects(:insert_one).with(has_entries(new_values)).returns(insert_report )

    delete_result = mock( deleted_count: 1 )
    CollectionLA.expects(:delete_one).with( ){ |qualifier, new_doc|
      has_valid_unlock_or_my_qualifier( qualifier, {'_id' => 3}, @caller.signature )
    }.returns( delete_result )

    doc.save(true,@caller, in_collection:CollectionFailedLA)
    assert_equal 'prepare to die', doc.message
    assert_in_delta sleep_between_create_and_update, ( doc.updated_timestamp - original_updated_timestamp  ), 0.5
  end

  def test_delete
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_delete = 2

    changed_values = { 'message' => 'prepare to die' }
    insert_report=mock
    insert_report.expects(:inserted_ids).returns( [ internal_id ])
    CollectionLA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentLA.create_one_locked( values, @caller )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_delete
    delete_result = mock( deleted_count: 1)
    CollectionLA.expects(:delete_one).with(){ |qualifier, new_doc|
      has_valid_unlock_or_my_qualifier( qualifier, {'_id' => 3}, @caller.signature )
    }.returns( delete_result )
    doc.delete( @caller )
  end

  def test_default_locking_agent
    DocumentLA.default_locking_agent = @caller
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_update = 2

    insert_report=mock(inserted_ids:[ internal_id ])
    CollectionLA.expects( :insert_one ).with( has_entries(values )).returns( insert_report )
    doc = DocumentLA.create_one_locked( values )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_update

    doc.message = "prepare to die"
    changed_values = { 'message' => 'prepare to die' }
    new_values = values.merge( changed_values )
    original_updated_timestamp = doc.updated_timestamp
    insert_report = mock( inserted_ids: [3])
    CollectionFailedLA.expects(:insert_one).with(has_entries(new_values)).returns(insert_report )

    delete_result = mock( deleted_count: 1 )
    CollectionLA.expects(:delete_one).with( ){ |qualifier, new_doc|
      has_valid_unlock_or_my_qualifier( qualifier, {'_id' => 3}, @caller.signature )
    }.returns( delete_result )

    doc.save( in_collection: CollectionFailedLA)
    assert_equal 'prepare to die', doc.message
    assert_in_delta sleep_between_create_and_update, ( doc.updated_timestamp - original_updated_timestamp  ), 0.5

  end

  def test_force_reset_expired_locks
    CollectionLA.expects(:update_many).with(){ |qual,set|
      has_locked_until( qual ) && set == { '$set' => { '_locked' => false}}
    }
    DocumentLA.force_reset_expired_locks
  end
end
