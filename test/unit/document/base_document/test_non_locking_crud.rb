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
require_relative '../../../helpers/coverage_helper'

require_relative '../../../../lib/armagh/document/base_document/document'
require_relative '../../../../lib/armagh/connection/mongo_error_handler'
require 'test/unit'
require 'mocha/test_unit'

class CollectionA; end
class CollectionFailedA; end

class DocumentA < Armagh::BaseDocument::Document
  def self.default_collection; CollectionA; end
  delegated_attr_accessor :name
  delegated_attr_accessor :message
end

class TestBaseDocumentNonLockingCRUD < Test::Unit::TestCase

  def setup
  end

  def shutdown
    Object.send(:remove_const, :CollectionA)
    Object.send(:remove_const, :DocumentA)
  end


  def test_create_one
    values = { 'name' => 'inigo montoya' }

    insert_report=mock( inserted_ids: [1])
    CollectionA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentA.create_one( values )
    assert_equal 'inigo montoya', doc.name
    assert_equal 1, doc.internal_id
  end

  def test_create_one_mongo_error
    values = { 'name' => 'inigo montoya' }

    CollectionA.expects( :insert_one ).with( has_entries(values) ).raises( Mongo::Error::MaxBSONSize)
    assert_raises Armagh::Connection::DocumentSizeError do
      doc = DocumentA.create_one( values )
    end
  end

  def test_find_one
    qualifier = { '_id' => 2 }
    values = qualifier.merge( { 'message' => 'you keeled my father' } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.find_one( qualifier )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
  end

  def test_find_one_not_found
    qualifier = { '_id' => 2 }
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.find_one( qualifier )
    assert_nil doc
  end

  def test_find_one_mongo_error
    qualifier = { '_id' => 2 }
    CollectionA.expects(:find).with( qualifier ).raises( Mongo::Error.new( 'oops' ) )
    assert_raises Armagh::Connection::ConnectionError.new('An unexpected connection error occurred from Document: oops.') do
      DocumentA.find_one( qualifier )
    end
  end

  def test_find_or_create_one_found
    qualifier = { '_id' => 2 }
    values = qualifier.merge( { 'message' => 'you keeled my father' } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.find_or_create_one( qualifier, {} )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
  end

  def test_find_or_create_one_created
    values = { 'name' => 'inigo montoya' }
    qualifier = values

    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )

    insert_report=mock
    insert_report.expects(:inserted_ids).returns( [ 1 ])
    CollectionA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentA.find_or_create_one( qualifier, values )
    assert_equal 'inigo montoya', doc.name
    assert_equal 1, doc.internal_id
  end

  def test_find_one_by_internal_id
    internal_id = 2
    qualifier = { '_id' => internal_id }
    values = qualifier.merge( { 'message' => 'you keeled my father' } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.find_one_by_internal_id( internal_id )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
  end

  def test_get
    internal_id = 2
    qualifier = { '_id' => internal_id }
    values = qualifier.merge( { 'message' => 'you keeled my father' } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.get( internal_id )
    assert_equal 2, doc.internal_id
    assert_equal 'you keeled my father', doc.message
  end

  def test_find_one_by_document_id
    internal_id = 2
    document_id = 'fred'
    qualifier = {'document_id' => document_id}
    values = qualifier.merge( { 'message' => 'you keeled my father', '_id' => 2 } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    doc = DocumentA.find_one_by_document_id( document_id )
    assert_equal 2, doc.internal_id
    assert_equal 'fred', doc.document_id
    assert_equal 'you keeled my father', doc.message
  end

  def test_find_one_image_by_internal_id
    internal_id = 2
    qualifier = { '_id' => internal_id }
    values = qualifier.merge( { 'message' => 'you keeled my father' } )
    mongo_return = mock
    mongo_return.expects( :limit ).with(1).returns( [values] )
    CollectionA.expects(:find).with( qualifier ).returns( mongo_return )
    image = DocumentA.find_one_image_by_internal_id( internal_id )
    assert_kind_of Hash, image
    assert_equal 2, image['_id']
    assert_equal 'you keeled my father', image['message']
  end

  def test_create_change_then_save
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_update = 2

    changed_values = { 'message' => 'prepare to die' }
    insert_report=mock(inserted_ids: [ internal_id ])
    CollectionA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentA.create_one( values )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_update

    doc.message = "prepare to die"

    new_values = values.merge( changed_values )
    original_updated_timestamp = doc.updated_timestamp
    CollectionA.expects(:replace_one).with(qualifier,has_entries(new_values), {:upsert => true})
    doc.save
    assert_equal 'prepare to die', doc.message
    assert_in_delta sleep_between_create_and_update, ( doc.updated_timestamp - original_updated_timestamp  ), 0.5
  end

  def test_create_change_collection_then_save
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_update = 2

    insert_report=mock(inserted_ids:[ internal_id ])
    CollectionA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentA.create_one( values )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_update

    doc.message = "prepare to die"
    changed_values = { 'message' => 'prepare to die' }
    new_values = values.merge( changed_values )
    original_updated_timestamp = doc.updated_timestamp
    insert_report = mock( inserted_ids: [3])
    CollectionFailedA.expects(:insert_one).with(has_entries(new_values)).returns(insert_report )
    CollectionA.expects(:delete_one).with( qualifier ).returns( mock( deleted_count: 1 ))
    doc.save( in_collection: CollectionFailedA )
    assert_equal 'prepare to die', doc.message
    assert_in_delta sleep_between_create_and_update, ( doc.updated_timestamp - original_updated_timestamp  ), 0.5
    assert_equal CollectionFailedA, doc.instance_variable_get( :@_collection ), CollectionFailedA
  end


  def test_delete
    internal_id = 3
    qualifier = { '_id' => internal_id }
    values = { 'name' => 'inigo montoya', 'message' => 'you keeled my father' }
    sleep_between_create_and_delete = 2

    changed_values = { 'message' => 'prepare to die' }
    insert_report=mock
    insert_report.expects(:inserted_ids).returns( [ internal_id ])
    CollectionA.expects( :insert_one ).with( has_entries(values) ).returns( insert_report )
    doc = DocumentA.create_one( values )
    assert_equal 'inigo montoya', doc.name
    assert_equal internal_id, doc.internal_id

    sleep sleep_between_create_and_delete
    CollectionA.expects(:delete_one).with(qualifier)
    doc.delete
  end

end
