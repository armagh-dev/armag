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

require_relative '../../../lib/connection'

require 'test/unit'
require 'mocha/test_unit'

class TestConnection < Test::Unit::TestCase

  def setup
    Armagh::Connection.clear_indexed_doc_collections
    mock_mongo
  end

  def mock_mongo
    @connection = mock
    instance = mock
    instance.stubs(:connection).returns(@connection)


    @admin_connection = mock
    admin_instance = mock
    admin_instance.stubs(:connection).returns(@admin_connection)

    @cluster = mock
    @connection.stubs(:cluster).returns(@cluster)

    @database = mock
    @connection.stubs(:database).returns(@database)

    Armagh::Connection::MongoConnection.stubs(:instance).returns(instance)
    Armagh::Connection::MongoAdminConnection.stubs(:instance).returns(admin_instance)
  end

  def test_all_document_collections
    indexes = mock
    indexes.expects(:create_one).twice
    documents = stub(name: 'documents', indexes: indexes)
    sometype1 = stub(name: 'documents.SomeType1', indexes: indexes)
    sometype2 = stub(name: 'documents.SomeType2', indexes: indexes)
    unrelated = stub(name: 'unrelated', indexes: indexes)

    @connection.expects(:collections).returns([documents, sometype1, sometype2, unrelated])

    @connection.expects(:[]).with('documents').returns(documents)

    all_collections = Armagh::Connection.all_document_collections
    assert_include all_collections, documents
    assert_include all_collections, sometype1
    assert_include all_collections, sometype2
    assert_not_include all_collections, unrelated
    assert_equal documents, all_collections.first, 'documents is expected to be first'
  end

  def test_documents
    @connection.expects(:[]).with('documents')
    Armagh::Connection.stubs(:index_doc_collection).once
    Armagh::Connection.documents
  end

  def test_document_published_collection
    @connection.expects(:[]).with('documents.test_type')
    Armagh::Connection.stubs(:index_doc_collection).once
    Armagh::Connection.documents('test_type')
  end

  def test_collection_history
    @connection.expects(:[]).with('collection_history')
    Armagh::Connection.collection_history
  end

  def test_failures
    @connection.expects(:[]).with('failures')
    Armagh::Connection.failures
  end

  def test_config
    @connection.expects(:[]).with('config')
    Armagh::Connection.config
  end

  def test_users
    @connection.expects(:[]).with('users')
    Armagh::Connection.users
  end

  def test_status
    @connection.expects(:[]).with('status')
    Armagh::Connection.status
  end

  def test_log
    @connection.expects(:[]).with('log')
    Armagh::Connection.log
  end

  def test_resource_config
    @admin_connection.expects(:[]).with('resource')
    Armagh::Connection.resource_config
  end

  def test_resource_log
    @admin_connection.expects(:[]).with('log')
    Armagh::Connection.resource_log
  end

  def test_master_no_master
    result = mock
    result.expects(:documents).returns([{'ismaster' => false}])
    @database.expects(:command).with(ismaster: 1).returns(result)
    assert_false Armagh::Connection.master?
  end

  def test_master
    result = mock
    result.expects(:documents).returns([{'ismaster' => true}])
    @database.expects(:command).with(ismaster: 1).returns(result)
    assert_true Armagh::Connection.master?
  end

  def test_primaries
    servers = [
        stub(address: stub(host: '10.10.10.10'), primary?: true),
        stub(address: stub(host: '10.10.10.11'), primary?: false),
        stub(address: stub(host: '10.10.10.12'), primary?: true),
        stub(address: stub(host: '10.10.10.13'), primary?: false)
    ]
    @cluster.expects(:servers).returns(servers)
    assert_equal %w(10.10.10.10 10.10.10.12), Armagh::Connection.primaries
  end

  def test_can_connect_no_servers
    @cluster.expects(:servers).returns([])
    assert_false Armagh::Connection.can_connect?
  end

  def test_can_connect_servers_true
    server = mock('object)')
    server.stubs(:connectable?).returns(true)
    @cluster.expects(:servers).returns([server])
    assert_true Armagh::Connection.can_connect?
  end

  def test_can_connect_servers_false
    server = mock('object)')
    server.stubs(:connectable?).returns(false)
    @cluster.expects(:servers).returns([server])
    assert_false Armagh::Connection.can_connect?
  end

  def test_can_connect_servers_error
    server = mock('object)')
    server.stubs(:connectable?).raises (RuntimeError.new('error'))
    @cluster.expects(:servers).returns([server])
    assert_false Armagh::Connection.can_connect?
  end

  def test_setup_indexes
    config_indexes = mock
    doc_indexes = mock
    config = stub(indexes: config_indexes)
    @connection.stubs(:[]).with('config').returns(config)
    Armagh::Connection.stubs(:all_document_collections).returns([stub(name: 'collection_name', indexes: doc_indexes)])

    config_indexes.expects(:create_one).with({'type' => 1, 'name'=>1, 'timestamp'=>-1}, {unique: true, name: 'types'})
    doc_indexes.expects(:create_one).twice

    Armagh::Connection.setup_indexes
  end

  def test_setup_indexes_error
    e = RuntimeError.new('error')
    config_indexes = mock
    doc_indexes = mock
    config = stub(indexes: config_indexes)
    @connection.stubs(:[]).with('config').returns(config)
    Armagh::Connection.stubs(:all_document_collections).returns([stub(name: 'collection_name', indexes: doc_indexes)])
    config_indexes.expects(:create_one).raises(e)
    assert_raise(Armagh::Errors::IndexError){Armagh::Connection.setup_indexes}
  end

  def test_index_doc_collection
    indexes = mock
    indexes.expects(:create_one).twice
    collection = mock
    collection.stubs(:name).returns('test_name').twice
    collection.stubs(:indexes).returns(indexes).twice
    Armagh::Connection.index_doc_collection(collection)
    Armagh::Connection.index_doc_collection(collection) # Make sure we aren't triggering reindexing
  end

  def test_index_doc_collection_error
    e = RuntimeError.new('error')
    indexes = mock
    indexes.expects(:create_one).raises(e)
    collection = mock
    collection.stubs(:name).returns('test_name')
    collection.stubs(:indexes).returns(indexes)
    assert_raise(Armagh::Errors::IndexError){Armagh::Connection.index_doc_collection(collection)}
  end
end