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
require_relative '../../lib/launcher/launcher'
require_relative '../../lib/admin/application/api'

require 'test/unit'
require 'mocha/test_unit'

require 'rack/test'

require 'fileutils'

require 'mongo'

module Armagh
  module StandardActions
    class TIAATestCollect < Actions::Collect
      define_output_docspec 'output_type', 'action description', default_type: 'OutputDocument', default_state: Armagh::Documents::DocState::READY
      define_parameter name: 'p1', type: 'integer', required: 'true', description: 'desc', default: 42, group: 'params'
    end
  end
end

class TestIntegrationApplicationAPI < Test::Unit::TestCase

  def app
    Sinatra::Application
  end

  def self.startup
    puts 'Starting Mongo'
    MongoSupport.instance.start_mongo
    load File.expand_path '../../../bin/armagh-application-admin', __FILE__
    include Rack::Test::Methods
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

  def setup
    MongoSupport.instance.clean_database
    MongoSupport.instance.clean_replica_set

    @logger = mock
    @logger.stubs(:fullname).returns('some::logger::name')
    @logger.stubs(:any)
    @logger.stubs(:debug)
    @api = Armagh::Admin::Application::API.instance

    authorize 'any', 'secret'
  end

  def test_get_status
    launcher_fake_status = {
      '_id'          => 'host.example.com',
      'versions'     => { 'thing' => 1 },
      'last_update'  => 'a time',
      'status'       => 'peachy',
      'agents'       => [ 'we are all cool' ]
    }

    get '/status.json' do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    Armagh::Connection.status.insert_one( launcher_fake_status )

    get '/status.json' do
      assert last_response.ok?
      assert_equal [launcher_fake_status], JSON.parse(last_response.body)
    end
  end

  def test_get_status_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_status).raises(e)

    get '/status.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_create_launcher
    test_config = {
      'num_agents' => '1',
      'update_frequency' => '60',
      'checkin_frequency' => '60',
      'log_level' => 'debug'
    }

    post '/launcher.json', test_config.to_json do
      assert last_response.ok?
      response_hash = JSON.parse(last_response.body)
      assert_equal test_config, response_hash.dig('values', 'launcher')
      assert_equal('Armagh::Launcher', response_hash['type'])
    end
  end

  def test_create_launcher_error
    test_config = {
      'num_agents' => '1',
      'update_frequency' => '60',
      'checkin_frequency' => '60',
      'log_level' => 'debug'
    }

    e = RuntimeError.new('Bad')
    @api.expects(:create_launcher_configuration).raises(e)

    post '/launcher.json', test_config.to_json do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
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

    get '/documents/counts.json' do
      assert last_response.ok?
      counts_in_db = JSON.parse(last_response.body)
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

  def test_get_document_counts_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_document_counts).raises(e)

    get '/documents/counts.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_create_action_configuration_good

    test_config = {
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect',
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *', 'archive' => false},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    workflow = Armagh::Actions::Workflow.new( @logger, Armagh::Connection.config )

    action = nil

    post '/action.json', test_config.to_json do
      assert last_response.ok?
      assert_equal 'success', JSON.parse(last_response.body)
    end

    assert_nothing_raised do
      workflow.refresh
      action = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end

    assert action.is_a?( Armagh::StandardActions::TIAATestCollect )
    assert_equal 42, action.config.params.p1
  end

  def test_create_action_configuration_bad_duplicate_name
    test_config = {
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect',
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *', 'archive' => false},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    post '/action.json', test_config.to_json do
      assert last_response.ok?
      assert_equal 'success', JSON.parse(last_response.body)
    end

    post '/action.json', test_config.to_json do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal('Armagh::Actions::ConfigurationError', response_hash.dig('error_detail', 'class'))
      assert_equal('Action named my_fred_action already exists.', response_hash.dig('error_detail', 'message'))
    end
  end

  def test_create_action_configuration_bad_config
    test_config = {
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect',
      'action' => { 'name' => 'my_fred_action' },
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    post '/action.json', test_config.to_json do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal('Armagh::Actions::ConfigurationError', response_hash.dig('error_detail', 'class'))
      assert_equal('Unable to create configuration Armagh::StandardActions::TIAATestCollect my_fred_action: collect schedule: type validation failed: value cannot be nil', response_hash.dig('error_detail', 'message'))
    end

    #TODO - figure out where's best to return the validation param set
  end

  def test_update_action_configuration_good

    test_config = {
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect',
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *', 'archive' => false},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    workflow = Armagh::Actions::Workflow.new( @logger, Armagh::Connection.config )

    action = nil
    assert_nothing_raised do
      @api.create_action_configuration( test_config )
      workflow.refresh(true)
      action = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end

    assert action.is_a?( Armagh::StandardActions::TIAATestCollect )
    assert_equal 42, action.config.params.p1

    test_config[ 'params' ] = { 'p1' => 100 }

    action2 = nil
    assert_nothing_raised do
      @api.update_action_configuration( test_config )
      workflow.refresh(true)
      action2 = workflow.instantiate_action( 'my_fred_action', self, @logger, nil )
    end

    assert_equal 100, action2.config.params.p1
  end

  def test_activate_action
    test_action_config = {
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect',
      'action' => { 'name' => 'my_fred_action' },
      'collect' => { 'schedule' => '0 * * * *', 'archive' => false},
      'output' => { 'doctype' => [ 'my_fred_doc', 'ready' ]}
    }

    test_config = [['Armagh::StandardActions::TIAATestCollect', 'my_fred_action']]

    post '/action.json', test_action_config.to_json do
      assert last_response.ok?
      assert_equal 'success', JSON.parse(last_response.body)
    end

    post '/actions/activate.json', test_config.to_json do
      assert last_response.ok?
      assert_equal 'success', JSON.parse(last_response.body)
    end
  end

  def test_activate_action_security
    test_config = [['raise "KABOOM"','my_fred_action']]

    post '/actions/activate.json', test_config.to_json do
      response_hash = JSON.parse(last_response.body)
      assert_not_equal('KABOOM', response_hash.dig('error_detail', 'message'))
    end
  end

  def test_activate_action_error
    e = RuntimeError.new('Bad')

    @api.expects(:activate_actions).raises(e)
    test_config = [['Armagh::StandardActions::TIAATestCollect', 'my_fred_action']]

    post '/actions/activate.json', test_config.to_json do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_get_documents
    type = 'TestType'
    get '/documents.json', {doc_type: type} do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    doc = Armagh::Document.create(type: type, content: { 'text' => 'bogusness' }, metadata: {},
                                  pending_actions: [], state: Armagh::Documents::DocState::PUBLISHED, document_id: 'test-id',
                                  collection_task_ids: [ '123' ], document_timestamp: Time.now, title: 'Test Document' )

    get '/documents.json', {doc_type: type} do
      assert last_response.ok?
      found_docs = JSON.parse(last_response.body)
      assert_kind_of Array, found_docs
      assert_equal 1, found_docs.length
      assert_equal doc.document_id, found_docs.first['document_id']
      assert_equal doc.title, found_docs.first['title']
    end
  end

  def test_get_documents_error
    e = RuntimeError.new('Bad')

    @api.expects(:get_documents).raises(e)
    get '/documents.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_get_document
    get '/document.json' do
      assert last_response.ok?
      assert_nil JSON.parse(last_response.body)
    end

    doc = Armagh::Document.create(type: 'TestType', content: { 'text' => 'bogusness' }, metadata: {},
                                  pending_actions: [], state: Armagh::Documents::DocState::PUBLISHED, document_id: 'test-id',
                                  collection_task_ids: [ '123' ], document_timestamp: Time.now, title: 'Test Document' )
    doc.save

    get '/document.json', {type: doc.type, document_id: doc.document_id} do
      assert last_response.ok?
      found_doc = JSON.parse(last_response.body)
      assert_equal doc.document_id, found_doc['document_id']
      assert_equal doc.title, found_doc['title']
    end
  end

  def test_get_document_error
    e = RuntimeError.new('Bad')

    @api.expects(:get_document).raises(e)
    get '/document.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_document_failures
    count = 10
    count.times do |i|
      doc = Armagh::Document.create(type: 'TestType', content: { 'text' => 'bogusness' }, metadata: {},
                              pending_actions: [], state: Armagh::Documents::DocState::READY, document_id: "id_#{i}",
                              collection_task_ids: [ '123' ], document_timestamp: Time.now )
      doc.add_dev_error('test_action', 'details')
      doc.save
    end

    failed_docs = nil

    get '/documents/failures.json' do
      assert last_response.ok?
      failed_docs = JSON.parse(last_response.body)
    end

    assert_equal(count, failed_docs.length)

    ids = failed_docs.collect{|d| d['document_id']}
    count.times do |i|
      assert_include(ids, "id_#{i}")
    end
  end

  def test_document_failures_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_failed_documents).raises(e)

    get '/documents/failures.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_version
    get '/version.json' do
      assert last_response.ok?
      response = JSON.parse(last_response.body)
      assert_equal Armagh::VERSION, response['armagh']
      assert_equal Armagh::StandardActions::VERSION, response.dig('actions', 'standard')
    end
  end

  def test_get_action
    test_config1 = {
      'collect' => {'schedule' => '0 * * * *', 'archive' => 'false'},
      'action' => {'name' => 'a1', 'active' => 'true'},
      'input' => {'docspec' => '__COLLECT__a1:ready'},
      'output' => {'output_type' => 'OutputDocument:ready'},
      'params' => {'p1' => '42'},
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect'
    }

    test_config2 = {
      'collect' => {'schedule' => '0 * * * *', 'archive' => 'false'},
      'action' => {'name' => 'a2', 'active' => 'false'},
      'input' => {'docspec' => '__COLLECT__a2:ready'},
      'output' => {'output_type' => 'OutputDocument:ready'},
      'params' => {'p1' => '42'},
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect'}

    post '/action.json', test_config1.to_json do
      assert last_response.ok?
    end

    post '/action.json', test_config2.to_json do
      assert last_response.ok?
    end

    get '/action.json', params={'name' => 'a2'} do
      assert last_response.ok?
      response = JSON.parse(last_response.body)
      assert_equal(test_config2, response)
    end
  end

  def test_get_action_no_name
    get '/action.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal({'error_detail' =>{'message' => "Request must include a non-empty parameter 'name'"}}, response_hash)
    end
  end

  def test_get_action_none
    get '/action.json', params={'name' => 'does_not_exist'} do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal({'error_detail' =>{'message' => "No action named 'does_not_exist' was found."}}, response_hash)
    end
  end

  def test_get_action_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_action_config).raises(e)

    get '/action.json', params={'name' => 'whatever'} do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end

  def test_get_actions
    test_config1 = {
      'collect' => {'schedule' => '0 * * * *', 'archive' => 'false'},
      'action' => {'name' => 'a1', 'active' => 'true'},
      'input' => {'docspec' => '__COLLECT__a1:ready'},
      'output' => {'output_type' => 'OutputDocument:ready'},
      'params' => {'p1' => '42'},
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect'
    }

    test_config2 = {
      'collect' => {'schedule' => '0 * * * *', 'archive' => 'false'},
      'action' => {'name' => 'a2', 'active' => 'false'},
      'input' => {'docspec' => '__COLLECT__a2:ready'},
      'output' => {'output_type' => 'OutputDocument:ready'},
      'params' => {'p1' => '42'},
      'action_class_name' => 'Armagh::StandardActions::TIAATestCollect'}

    post '/action.json', test_config1.to_json do
      assert last_response.ok?
    end

    post '/action.json', test_config2.to_json do
      assert last_response.ok?
    end

    get '/actions.json' do
      assert last_response.ok?
      response = JSON.parse(last_response.body)
      assert_equal([test_config1, test_config2], response)
    end
  end

  def test_get_actions_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_action_configs).raises(e)

    get '/actions.json' do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('error_detail', 'message'))
    end
  end
end