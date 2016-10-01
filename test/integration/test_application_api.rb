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

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require_relative '../../lib/launcher/launcher'
require_relative '../../lib/admin/application/api'
require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

module Armagh
  module StandardActions
    class TIAATestCollect < Actions::Collect
      define_parameter name: 'p1', type: 'integer', required: 'true', description: 'desc', default: 42, group: 'params'
    end
  end
end

class TestIntegrationApplicationAPI < Test::Unit::TestCase

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo
    Armagh::Connection::MongoConnection.instance.connection.database.collections.each{ |col| col.drop }
    Armagh::Connection::MongoAdminConnection.instance.connection.database.collections.each{ |col| col.drop }
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
    @api = Armagh::Admin::Application::API.instance

  end

  def test_get_status
    
    launcher_fake_status = {
      '_id'          => 'host.example.com',
      'versions'     => { 'thing' => 1 },
      'last_update'  => 'a time',
      'status'       => 'peachy',
      'agents'       => [ 'we are all cool' ]
    }
    
    Armagh::Connection.status.insert_one( launcher_fake_status )
    
    assert_equal [launcher_fake_status], @api.get_status

  end
  
  def test_get_document_counts
    
    ('a'..'e').each_with_index do |type,type_i|
      (20+type_i).times do |i|
        Armagh::Document.create( type: type, content: { 'text' => 'bogusness' }, metadata: {},
        pending_actions: [], state: Armagh::Documents::DocState::READY, document_id: "#{type}-#{i}",
        collection_task_ids: [ '123' ], document_timestamp: Time.now )
      end
    end
    ('c'..'e').each_with_index do |type,type_i|
      (100+type_i).times do |i|
        Armagh::Document.create( type: type, content: { 'text' => 'bogusness' }, metadata: {},
        pending_actions: [], state: Armagh::Documents::DocState::PUBLISHED, document_id: "#{type}-p-#{i}",
        collection_task_ids: [ '123' ], document_timestamp: Time.now )
      end
    end
    
    counts_in_db = {}
    assert_nothing_raised do 
      counts_in_db = @api.get_document_counts
    end
    
    assert_equal(  {
      "documents" => {
        "a:ready" => 20,
        "b:ready" => 21, 
        "c:ready" => 22, 
        "d:ready" => 23, 
        "e:ready" => 24 
      }, 
      "documents.c" => { "c:published"=>100 }, 
      "documents.d" => { "d:published"=>101 },
      "documents.e" => { "e:published"=>102 } 
      }, counts_in_db )
  end
  
  def test_create_action_configuration_good
    
    test_config = { 
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *'},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    workflow = Armagh::Actions::Workflow.new( @logger, Armagh::Connection.config )
    
    action = nil
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
      workflow.refresh
      action = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end
    
    assert action.is_a?( Armagh::StandardActions::TIAATestCollect )
    assert_equal 42, action.config.params.p1
    
  end
  
  def test_create_action_configuration_bad_duplicate_name 

    test_config = { 
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *'},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }
    
    action = nil
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
    end
    
    e = assert_raises( Armagh::Actions::ConfigurationError ) do
      @api.create_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
    end
    assert_equal "Action named my_fred_action already exists.", e.message
  end  
    
  def test_create_action_configuration_bad_config 

    test_config = { 
      'action' => { 'name' => 'my_fred_action' },
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }
    
    action = nil
    e = assert_raises( Armagh::Actions::ConfigurationError ) do
      @api.create_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
    end

    #TODO - figure out where's best to return the validation param set
  end  

  def test_update_action_configuration_good
    
    test_config = { 
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *'},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }
    
    workflow = Armagh::Actions::Workflow.new( @logger, Armagh::Connection.config )

    action = nil
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
      workflow.refresh
      action = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end
    
    assert action.is_a?( Armagh::StandardActions::TIAATestCollect )
    assert_equal 42, action.config.params.p1

    test_config[ 'params' ] = { 'p1' => 100 }    
    
    action2 = nil
    assert_nothing_raised do
      @api.update_action_configuration( 'Armagh::StandardActions::TIAATestCollect', test_config )
      workflow.refresh
      action2 = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end
    
    assert_equal 100, action2.config.params.p1
  end
end