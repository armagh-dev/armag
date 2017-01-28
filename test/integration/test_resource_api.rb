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
ENV['RACK_ENV'] = 'test'

require_relative '../helpers/coverage_helper'

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require_relative '../../lib/admin/resource/api'

require 'test/unit'
require 'mocha/test_unit'

require 'rack/test'

require 'mongo'

class TestIntegrationResourceAPI < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def self.startup
    puts 'Starting Mongo'
    MongoSupport.instance.start_mongo
    Armagh::Connection::MongoConnection.instance.connection.database.collections.each{ |col| col.drop }
    load File.expand_path '../../../bin/armagh-resource-admin', __FILE__
    include Rack::Test::Methods
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
    
    @api = Armagh::Admin::Resource::API.instance

    @collections = [:documents,
                    :collection_history,
                    :failures,
                    :config,
                    :users,
                    :status,
                    :log,
                    :resource_config,
                    :resource_log
    ]

    authorize 'any', 'secret'
  end

  def fill_collections
    @collections.each do |coll|
      Armagh::Connection.send(coll).insert_one({'imin' => coll.to_s, 'timestamp' => Time.now})
    end

    @collections.each do |coll|
      assert_equal 1, Armagh::Connection.send(coll).find.count
    end
  end

  def implode(confirmed)
    fill_collections

    implode_timestamp = Time.now
    json = {'confirmed' => confirmed}.to_json

    yield json

    expected_count = (confirmed ? 0 : 1)
    @collections.each do |coll|
      actual_count = Armagh::Connection.send(coll).find({'timestamp' => {'$lt' => implode_timestamp}}).count
      assert_equal expected_count, actual_count, "Collection #{coll} expected to have #{expected_count} documents but had #{actual_count} documents.  #{Armagh::Connection.send(coll).find.to_a}"
    end
  end

  def test_implode_with_confirmation
    implode(true) do |param|
      post '/implode.json', param do
        assert last_response.ok?
        assert_equal({'result' => 'Implosion complete'}, JSON.parse(last_response.body))
      end
    end
  end

  def test_implode_without_confirmation
    implode(false) do |param|
      post '/implode.json', param do
        assert last_response.server_error?
        assert_equal({'error_detail' => {'message' => 'No implosion.  You must post data {"confirmed": true}'}}, JSON.parse(last_response.body))
      end
    end
  end
end