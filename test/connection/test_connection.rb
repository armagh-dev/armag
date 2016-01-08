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
require_relative '../../lib/connection'
require 'test/unit'
require 'mocha/test_unit'

class TestConnection < Test::Unit::TestCase

  def setup
    mock_mongo
  end

  def mock_mongo
    @connection = mock('object')

    instance = mock('object')
    instance.stubs(:connection).returns(@connection)

    @cluster = mock('cluster')
    @connection.stubs(:cluster).returns(@cluster)

    Armagh::Connection::MongoConnection.stubs(:instance).returns(instance)
  end

  def test_documents
    @connection.expects(:[]).with('documents')
    Armagh::Connection.documents
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

end