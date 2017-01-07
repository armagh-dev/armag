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

require_relative '../helpers/coverage_helper'

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require_relative '../../lib/admin/resource/api'
require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestIntegrationResourceAPI < Test::Unit::TestCase

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    Singleton.__init__(Armagh::Connection::MongoAdminConnection)
    MongoSupport.instance.start_mongo
    Armagh::Connection::MongoConnection.instance.connection.database.collections.each{ |col| col.drop }
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

  def setup
    Armagh::Connection::MongoConnection.instance.connection.database.collections.each{ |col| col.drop }
    Armagh::Connection::MongoAdminConnection.instance.connection.database.collections.each{ |col| col.drop }
    Armagh::Connection.clear_indexed_doc_collections
    Armagh::Connection.setup_indexes    
    
    @logger = mock
    @api = Armagh::Admin::Resource::API.instance

  end

  def implode( confirmed )
    
    collections = [ :documents, 
      :collection_history,
      :failures,
      :config, 
      :users, 
      :status, 
      :log, 
      :resource_config, 
      :resource_log 
    ]
    
    collections.each do |coll|
      Armagh::Connection.send( coll ).insert_one( { 'imin' => coll.to_s })
    end
    
    collections.each do |coll|
      assert_equal 1, Armagh::Connection.send( coll ).find.count
    end
    
    assert_equal confirmed, @api.implode( confirmed )
    
    collections.each do |coll|
      assert_equal (confirmed ? 0 : 1 ), Armagh::Connection.send( coll ).find.count
    end
    
    
  end
  
  def test_implode_with_confirmation
    implode( true )
  end
  
  def test_implode_without_confirmation
    implode( false )
  end
end