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

require_relative '../../../lib/environment.rb'
Armagh::Environment.init

require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/connection'
require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestMongoAdminConnection < Test::Unit::TestCase

  def setup
    @config = {'ip' => '127.0.0.1', 'port' => 27017, 'str' => '', 'db' => 'armagh_admin'}
    Armagh::Configuration::FileBasedConfiguration.stubs(:load).returns(@config)
    @mongo_connection = Armagh::Connection::MongoAdminConnection.instance
  end

  def test_mongo_connection
    assert_kind_of(Mongo::Client, @mongo_connection.connection)
    Mongo::Client.any_instance.stubs(:create_from_uri)
    assert_kind_of(Mongo::Client, Class.new(Armagh::Connection::MongoAdminConnection).instance.connection)
  end

  def test_mongo_connection_no_config
    @config = {}
    Armagh::Configuration::FileBasedConfiguration.stubs(:load).returns(@config)
    e = assert_raise(Armagh::Errors::ConnectionError) {Class.new(Armagh::Connection::MongoAdminConnection).instance.connection}
    assert_equal('Insufficient connection info for admin connection. Ensure armagh_env.json contains Armagh::Connection::MongoAdminConnection[ ip, port, str, db].', e.message)
  end

  def test_mongo_connection_db_err
    root_error = RuntimeError.new('Connection Failure')
    Mongo::Client.stubs(:new).raises(root_error)
    e = assert_raise(Armagh::Errors::ConnectionError) {Class.new(Armagh::Connection::MongoAdminConnection).instance.connection}
    assert_equal('Unable to establish admin database connection.', e.message)
    assert_equal(root_error, e.cause)
  end
end
