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

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/connection'

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
    indexes.expects(:create_one).times(3)
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

  def test_published_document_collection
    indexes = mock('indexes')
    indexes.stubs(:create_one)
    documents = stub(name: 'documents', indexes: indexes)
    sometype1 = stub(name: 'documents.SomeType1', indexes: indexes)
    sometype2 = stub(name: 'documents.SomeType2', indexes: indexes)
    unrelated = stub(name: 'unrelated', indexes: indexes)

    @connection.expects(:collections).returns([documents, sometype1, sometype2, unrelated])

    all_published_collections = Armagh::Connection.all_published_collections
    assert_not_include all_published_collections, documents
    assert_include all_published_collections, sometype1
    assert_include all_published_collections, sometype2
    assert_not_include all_published_collections, unrelated
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

  def test_agent_status
    @connection.expects(:[]).with('agent_status')
    Armagh::Connection.agent_status
  end

  def test_launcher_status
    @connection.expects(:[]).with('launcher_status')
    Armagh::Connection.launcher_status
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
    assert_equal 'The database does not appear to be running.', Armagh::Connection.can_connect_message
  end

  def test_can_connect_servers_true
    server = mock
    connection = mock
    connection.expects(:ping).returns(true)
    server.stubs(:with_connection).yields(connection)
    @cluster.expects(:servers).returns([server])
    assert_true Armagh::Connection.can_connect?
    assert_nil Armagh::Connection.can_connect_message
  end

  def test_can_connect_servers_false
    server = mock
    connection = mock
    connection.expects(:ping).returns(false)
    server.stubs(:with_connection).yields(connection)
    @cluster.expects(:servers).returns([server])
    assert_false Armagh::Connection.can_connect?
    assert_nil Armagh::Connection.can_connect_message
  end

  def test_can_connect_servers_error
    server = mock
    connection = mock
    connection.expects(:ping).raises(RuntimeError.new('error message'))
    server.stubs(:with_connection).yields(connection)
    @cluster.expects(:servers).returns([server])
    assert_false Armagh::Connection.can_connect?
    assert_equal 'error message', Armagh::Connection.can_connect_message
  end

  def test_require_connection
    Armagh::Connection.expects(:can_connect?).returns(true)
    assert_nothing_raised{Armagh::Connection.require_connection}
  end

  def test_require_connection_none
    logger = mock('logger')
    logger.expects(:error)
    Armagh::Connection.expects(:can_connect?).returns(false)
    assert_raise(SystemExit){Armagh::Connection.require_connection(logger)}
  ensure
    # Restore the log env (since we deleted the mongo outputter)
    Armagh::Logging.init_log_env
  end

  def test_setup_indexes
    config_indexes = mock
    action_state_indexes = mock
    users_indexes = mock
    groups_indexes = mock
    doc_indexes = mock
    agent_status_indexes = mock
    semaphore_indexes = mock
    log_indexes = mock

    config = stub(indexes: config_indexes)
    action_state = stub(indexes: action_state_indexes)
    users = stub(indexes: users_indexes)
    groups = stub(indexes: groups_indexes)
    agent_status = stub(indexes: agent_status_indexes)
    semaphores = stub(indexes: semaphore_indexes)
    log = stub(indexes: log_indexes)

    @connection.stubs(:[]).with('config').returns(config)
    @connection.stubs(:[]).with('action_state').returns(action_state)
    @connection.stubs(:[]).with('users').returns(users)
    @connection.stubs(:[]).with('groups').returns(groups)
    @connection.stubs(:[]).with('agent_status').returns(agent_status)
    @connection.stubs(:[]).with('semaphores').returns(semaphores)
    @connection.stubs(:[]).with('log').returns(log)
    Armagh::Connection.stubs(:all_document_collections).returns([stub(name: 'collection_name', indexes: doc_indexes)])

    config_indexes.expects(:create_one).with({'type' => 1, 'name'=>1, 'timestamp'=>-1}, {unique: true, name: 'types'})
    action_state_indexes.expects(:create_one).with({'action_name' => 1}, {:unique => true, :name => 'names'})
    users_indexes.expects(:create_one).with({'username' => 1}, {:unique => true, :name => 'usernames'})
    groups_indexes.expects(:create_one).with({'name' => 1}, {:unique => true, :name => 'names'})
    agent_status_indexes.expects(:create_one).with({'hostname' => 1}, {:unique => false, :name => 'hostnames'})
    semaphore_indexes.expects(:create_one).with({'name' => 1}, {:unique => true, :name => 'names'})
    doc_indexes.expects(:create_one).times(3)
    log_indexes.expects(:create_one)

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
    assert_raise(Armagh::Connection::IndexError){Armagh::Connection.setup_indexes}
  end

  def test_index_doc_collection
    indexes = mock
    indexes.expects(:create_one).times(3)
    collection = mock
    collection.stubs(:name).returns('documents')
    collection.stubs(:indexes).returns(indexes).times(3)
    Armagh::Connection.index_doc_collection(collection)
    Armagh::Connection.index_doc_collection(collection) # Make sure we aren't triggering reindexing
  end

  def test_index_published_doc_collection
    indexes = mock
    indexes.expects(:create_one).times(4)
    collection = mock
    collection.stubs(:name).returns('documents.PublishedType')
    collection.stubs(:indexes).returns(indexes).times(4)
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
    assert_raise(Armagh::Connection::IndexError){Armagh::Connection.index_doc_collection(collection)}
  end
end