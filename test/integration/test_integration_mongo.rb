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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestIntegrationMongo < Test::Unit::TestCase

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

  def setup
    MongoSupport.instance.clean_database
  end

  def test_mongo_connection
    result = Armagh::Connection.documents.insert_one( { _id: 'test1', content: 'stuff' })
    assert_equal result.documents, [{ "n" => 1, "ok" => 1}]
  end
  
end
