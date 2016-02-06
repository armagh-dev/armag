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

require 'mongo'

class TestMongoAdminConnection < Test::Unit::TestCase

  def setup
    @mongo_connection = Armagh::Connection::MongoConnection.instance
  end
  
  def test_mongo_connection
    assert_kind_of(Mongo::Client, @mongo_connection.connection)
    Mongo::Client.any_instance.stubs(:create_from_uri)
    assert_kind_of(Mongo::Client, Class.new(Armagh::Connection::MongoAdminConnection).instance.connection)
  end

  def test_mongo_connection_no_env

    e = assert_raise do
      Class.new(Armagh::Connection::MongoAdminConnection).instance.connection
    end

    assert_equal('No admin connection string defined.', e.message)

  end

  def test_mongo_connection_db_err
    Mongo::Client.stubs(:new).raises(RuntimeError.new('Connection Failure'))

    e = assert_raise do
      Class.new(Armagh::Connection::MongoAdminConnection).instance.connection
    end

    assert_equal('Unable to establish admin database connection: Connection Failure', e.message)

  end
  
end
