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
require_relative '../helpers/integration_helper'
require_relative '../helpers/workflow_generator_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/launcher/launcher'
require_relative '../../lib/armagh/admin/application/api'

require 'test/unit'
require 'mocha/test_unit'
require 'rack/test'
require 'fileutils'
require 'etc'
require 'digest/md5'

require 'mongo'

TEST_DESCRIPTION = 'Yo ho ho and a bottle of rum.'
module Armagh
  module StandardActions
    class TIAATestCollect < Actions::Collect
      define_parameter name: 'p1', type: 'integer', required: 'true', description: 'desc', default: 42, group: 'params'
      def self.description
        TEST_DESCRIPTION
      end
    end
  end
end

class TestIntegrationApplicationAPI < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def self.startup
    load File.expand_path '../../../bin/armagh-application-admin', __FILE__
    include Rack::Test::Methods
  end

  def good_alice_in_db
    wf_set = Armagh::Actions::WorkflowSet.for_admin( Connection.config )
    @alice = wf_set.create_workflow( { 'workflow' => { 'name' => 'alice' }} )
    @alice.unused_output_docspec_check = false
    @alice_workflow_actions_config_values.each do |type,action_config_values|
      @alice.create_action_config(type, action_config_values)
    end
    @alice
  end

  def expect_alice_docs_in_db
    response = {
        'documents' => { 'a_alicedoc:ready'=>9, 'b_alicedocs_aggr:ready'=>20, 'a_freddoc:ready'=>400_000 },
        'failures'   => {'a_alicedoc:ready'=>3, 'a_freddoc:ready' => 100_000 },
        'a_alicedoc' => {'a_alicedoc:published'=>4},
        'b_alicedoc' => {'b_alicedoc:published'=>5}
    }
    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .at_least_once
        .with(["a_alicedoc", "b_alicedoc"])
        .returns( response  )
  end

  def expect_no_alice_docs_in_db
    response = {
        'documents' => {},
        'failures'   => {},
        'a_alicedoc' => {},
        'b_alicedoc' => {}
    }
    Armagh::Document
        .expects(:count_incomplete_by_doctype)
        .at_least_once
        .with(["a_alicedoc", "b_alicedoc"])
        .returns( response  )
  end

  def fake_agent_status
    {
        '_id'           => 'agent-123',
        'hostname'      => 'host.example.com',
        'task'          => { 'document' => '123', 'action' => '456' },
        'running_since' => 'a time',
        'idle_since'    => 'a time',
        'last_updated'   => 'a time',
        'status'        => 'peachy',
    }
  end

  def fake_launcher_status
    {
        '_id'          => 'host.example.com',
        'versions'     => { 'thing' => 1 },
        'last_updated'  => 'a time',
        'status'       => 'peachy',
    }
  end

  def setup
    @current_user = Etc.getpwuid(Process.uid).name
    MongoSupport.instance.clean_database
    MongoSupport.instance.clean_replica_set
    Connection.setup_indexes
    Armagh::Authentication.setup_authentication

    @alice_workflow_config_values = {'workflow'=>{'name'=>'alice'}}
    @alice_workflow_actions_config_values = WorkflowGeneratorHelper.workflow_actions_config_values_with_divide( 'alice' )

    @logger = mock
    @logger.stubs(:fullname).returns('some::logger::name')
    @logger.stubs(:any)
    @logger.stubs(:debug)
    @api = Armagh::Admin::Application::API.instance
    @test_username = 'superadmin_user'
    @test_password = 'superadmin_password'

    @test_user = Authentication::User.create(username: @test_username,
                                             password: @test_password,
                                             name: 'Super Admin',
                                             email: 'superadmin@example.com')

    @test_user.join_group(Authentication::Group.find_name('super_administrators'))
    @test_user.save

    authorize @test_username, @test_password
  end

  def user_with_role(role)
    role_key = role ? role.key : ''
    user = Authentication::User.create(username: "user_#{role_key}",
                                       password: "password_#{role_key}",
                                       name: 'test user',
                                       email: 'user@example.com')
    user.add_role(role) if role
    user.save
    user
  end

  def users_with_all_roles
    users = {}
    Authentication::Role.all.each do |role|
      users[role] = user_with_role(role)
    end
    users[nil] = user_with_role(nil)
    users
  end

  def test_get_agent_status
    get '/agent_status.json' do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    Armagh::Connection.agent_status.insert_one( fake_agent_status )

    get '/agent_status.json' do
      assert last_response.ok?
      assert_equal [fake_agent_status], JSON.parse(last_response.body)
    end
  end

  def test_get_launcher_status
    get '/launcher_status.json' do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    Armagh::Connection.launcher_status.insert_one( fake_launcher_status )

    get '/launcher_status.json' do
      assert last_response.ok?
      assert_equal [fake_launcher_status], JSON.parse(last_response.body)
    end
  end

  def test_get_status
    get '/status.json'do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    Armagh::Connection.launcher_status.insert_one( fake_launcher_status )
    Armagh::Connection.agent_status.insert_one( fake_agent_status )

    expected = fake_launcher_status
    expected['agents'] = [fake_agent_status]

    get '/status.json'do
      assert last_response.ok?
      assert_equal [expected],  JSON.parse(last_response.body)
    end
  end

  def test_get_agent_status_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_agent_status).raises(e)

    get '/agent_status.json' do
      assert last_response.server_error?
      server_error_detail = JSON.parse(last_response.body)[ 'server_error_detail']
      assert_equal e.class.to_s, server_error_detail[ 'class' ]
      assert_equal e.message, server_error_detail['message']
    end
  end

  def test_get_launcher_status_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_launcher_status).raises(e)

    get '/launcher_status.json' do
      assert last_response.server_error?
      server_error_detail = JSON.parse(last_response.body)[ 'server_error_detail']
      assert_equal e.class.to_s, server_error_detail[ 'class' ]
      assert_equal e.message, server_error_detail['message']
    end
  end

  def test_get_status_error
    e = RuntimeError.new('Bad')
    @api.expects(:get_status).raises(e)

    get '/status.json' do
      assert last_response.server_error?
      server_error_detail = JSON.parse(last_response.body)[ 'server_error_detail']
      assert_equal e.class.to_s, server_error_detail[ 'class' ]
      assert_equal e.message, server_error_detail['message']
    end
  end

  def test_launcher
    test_config = {
      'launcher' => {
        'num_agents' => '1',
        'update_frequency' => '60',
        'checkin_frequency' => '60',
        'log_level' => 'debug'
      }
    }

    post "/configuration/launcher/#{Launcher.config_name}.json", test_config.to_json do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end

    get "/configuration/launcher/#{Launcher.config_name}.json" do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end
  end

  def test_create_launcher_client_error
    test_config = {
      'launcher' => {
        'num_agents' => 'BAD',
        'update_frequency' => '60',
        'checkin_frequency' => '60',
        'log_level' => 'debug'
      }
    }

    post "/configuration/launcher/#{Launcher.config_name}.json", test_config.to_json do
      assert last_response.client_error?
      failure_detail = JSON.parse(last_response.body)['client_error_detail']
      expected_markup = {
          'type' => 'Armagh::Launcher',
          'parameters' => [
              {"name"=>"num_agents", "description"=>"Number of agents", "type"=>"positive_integer", "required"=>true, "default"=>1, "prompt"=>nil, "group"=>"launcher", "warning"=>nil, "error"=>"type validation failed: value 'BAD' cannot be cast as an integer", "value"=>nil, "options"=>nil},
              {"name"=>"update_frequency", "description"=>"Configuration refresh rate (seconds)", "type"=>"positive_integer", "required"=>true, "default"=>60, "prompt"=>nil, "group"=>"launcher", "warning"=>nil, "error"=>nil, "value"=>60, "options"=>nil},
              {"name"=>"checkin_frequency", "description"=>"Status update rate (seconds)", "type"=>"positive_integer", "required"=>true, "default"=>60, "prompt"=>nil, "group"=>"launcher", "warning"=>nil, "error"=>nil, "value"=>60, "options"=>nil},
              {"name"=>"log_level", "description"=>"Log level", "type"=>"populated_string", "required"=>true, "default"=>"info", "prompt"=>nil, "group"=>"launcher", "warning"=>nil, "error"=>nil, "value"=>"debug", "options"=>nil}
          ]}

      assert_equal'Invalid launcher config', failure_detail['message']
      assert_equal expected_markup, failure_detail['markup']
    end
  end

  def test_launchers
    test_config1 = {
      'launcher' => {
        'num_agents' => '1',
        'update_frequency' => '60',
        'checkin_frequency' => '60',
        'log_level' => 'debug'
      }
    }

    test_config2 = {
      'launcher' => {
        'num_agents' => '2',
        'update_frequency' => '60',
        'checkin_frequency' => '60',
        'log_level' => 'info'
      }
    }

    expected_result = {
      'launcher_1' => test_config1,
      'launcher_2' => test_config2
    }

    # Dummy Launcher 1
    dummy_1 = test_config1.deep_copy
    dummy_1['launcher']['num_agents'] = 3
    post '/configuration/launcher/launcher_1.json', dummy_1.to_json do
      assert last_response.ok?
    end

    sleep 1
    post '/configuration/launcher/launcher_1.json', test_config1.to_json do
      assert last_response.ok?
    end

    post '/configuration/launcher/launcher_2.json', test_config2.to_json do
      assert last_response.ok?, last_response.body
    end

    get '/configuration/launchers.json' do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      assert_equal expected_result, result
    end
  end

  def test_agent
    test_config = {
      'agent' => {
        'log_level' => 'debug',
      }
    }

    post '/configuration/agent.json', test_config.to_json do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end

    get '/configuration/agent.json' do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end
  end

  def test_create_agent_client_error
    test_config = {
      'agent' => {
        'something' => 'BAD',
        'log_level' => 'debug'
      }
    }

    post '/configuration/agent.json', test_config.to_json do
      assert last_response.client_error?
      failure_detail = JSON.parse(last_response.body)['client_error_detail']
      expected_markup = {
        'type' => 'Armagh::Agent',
        'parameters' => [
          {"name" => "log_level", "description" => "Logging level for agents", "type" => "populated_string", "required" => true, "default" => "info", "prompt" => nil, "group" => "agent", "warning" => nil, "error" => nil, "value" => "debug", "options" => nil},
          {"name" => "something", "description" => "non-existent", "type" => "string", "required" => false, "default" => nil, "prompt" => nil, "group" => "agent", "warning" => nil, "error" => "Configuration provided for parameter that does not exist", "value" => "BAD", "options" => nil}
        ]}

      assert_equal'Invalid agent config', failure_detail['message']
      assert_equal expected_markup, failure_detail['markup']
    end
  end

  def test_authentication
    test_config = {
      'authentication' => {
        'max_login_attempts' => '5',
        'min_password_length' => '10'
      }
    }

    post '/configuration/authentication.json', test_config.to_json do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end

    get '/configuration/authentication.json' do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end
  end

  def test_create_authentication_client_error
    test_config = {
      'authentication' => {
        'max_login_attempts' => '5',
        'min_password_length' => 'BAD'
      }
    }

    post '/configuration/authentication.json', test_config.to_json do
      assert last_response.client_error?
      failure_detail = JSON.parse(last_response.body)['client_error_detail']
      expected_markup = {
        'type' => 'Armagh::Authentication::Configuration',
        'parameters' => [
          {"default" => 3, "description" => "Maximum number of allowed failed login attempts before locking account.", "error" => nil, "group" => "authentication", "name" => "max_login_attempts", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => 5, "warning" => nil},
          {"default" => 8, "description" => "Minimum length of a password.", "error" => "type validation failed: value 'BAD' cannot be cast as an integer", "group" => "authentication", "name" => "min_password_length", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => nil, "warning" => nil}
        ]}

      assert_equal'Invalid authentication config', failure_detail['message']
      assert_equal expected_markup, failure_detail['markup']
    end
  end

  def test_archive
    test_config = {
      'sftp' => {
        'host' => 'localhost',
        'port' => '22',
        'username' => @current_user,
        'directory_path' => '/tmp/var/archive'
      },
      'archive' => {
        'max_archives_per_dir' => '100'
      }
    }

    post '/configuration/archive.json', test_config.to_json do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end

    get '/configuration/archive.json' do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = test_config
      assert_equal expected_result, result
    end
  end

  def test_create_archive_client_error
    test_config = {
      'sftp' => {
        'host' => 'localhost',
        'port' => 'BAD',
        'username' => @current_user,
        'directory_path' => '/tmp/var/archive'
      },
      'archive' => {
        'max_archives_per_dir' => 'BAD'
      }
    }

    post '/configuration/archive.json', test_config.to_json do
      assert last_response.client_error?
      failure_detail = JSON.parse(last_response.body)['client_error_detail']
      expected_markup = {
        'type' => 'Armagh::Utils::Archiver',
        'parameters' => [
          {"default" => nil, "description" => "SFTP host or IP", "error" => nil, "group" => "sftp", "name" => "host", "options" => nil, "prompt" => "host.example.com or 10.0.0.1", "required" => true, "type" => "populated_string", "value" => "localhost", "warning" => nil},
          {"default" => 22, "description" => "SFTP port", "error" => "type validation failed: value 'BAD' cannot be cast as an integer", "group" => "sftp", "name" => "port", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => nil, "warning" => nil},
          {"default" => "./", "description" => "SFTP base directory path", "error" => nil, "group" => "sftp", "name" => "directory_path", "options" => nil, "prompt" => nil, "required" => true, "type" => "populated_string", "value" => "/tmp/var/archive", "warning" => nil},
          {"default" => nil, "description" => "SFTP user name", "error" => nil, "group" => "sftp", "name" => "username", "options" => nil, "prompt" => "user", "required" => true, "type" => "populated_string", "value" => @current_user, "warning" => nil},
          {"default" => nil, "description" => "SFTP user password", "error" => nil, "group" => "sftp", "name" => "password", "options" => nil, "prompt" => "password", "required" => false, "type" => "encoded_string", "value" => nil, "warning" => nil},
          {"default" => nil, "description" => "SSH Key (not filename!) for SFTP connection", "error" => nil, "group" => "sftp", "name" => "key", "options" => nil, "prompt" => "password", "required" => false, "type" => "string", "value" => nil, "warning" => nil},
          {"default" => 5000, "description" => "Maximum number archives to store per subdirectory.", "error" => "type validation failed: value 'BAD' cannot be cast as an integer", "group" => "archive", "name" => "max_archives_per_dir", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => nil, "warning" => nil}
        ]}

      assert_equal(
        "Invalid archive config. Unable to create configuration for 'Armagh::Utils::Archiver' named 'default' because: \n" +
        "    Group 'sftp' Parameter 'port': type validation failed: value 'BAD' cannot be cast as an integer\n" +
        "    Group 'archive' Parameter 'max_archives_per_dir': type validation failed: value 'BAD' cannot be cast as an integer",
        failure_detail['message']
      )
      assert_equal expected_markup, failure_detail['markup']
    end
  end

  def test_create_archive_client_validation_error
    test_config = {
      'sftp' => {
        'host' => 'invalid.noragh.com',
        'port' => '22',
        'username' => 'invalid',
        'directory_path' => '/tmp/var/archive'
      },
      'archive' => {
        'max_archives_per_dir' => '100'
      }
    }

    post '/configuration/archive.json', test_config.to_json do
      assert last_response.client_error?
      failure_detail = JSON.parse(last_response.body)['client_error_detail']
      expected_markup = {
        'type' => 'Armagh::Utils::Archiver',
        'parameters' => [
          {"default" => nil, "description" => "SFTP host or IP", "error" => nil, "group" => "sftp", "name" => "host", "options" => nil, "prompt" => "host.example.com or 10.0.0.1", "required" => true, "type" => "populated_string", "value" => "invalid.noragh.com", "warning" => nil},
          {"default" => 22, "description" => "SFTP port", "error" => nil, "group" => "sftp", "name" => "port", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => 22, "warning" => nil},
          {"default" => "./", "description" => "SFTP base directory path", "error" => nil, "group" => "sftp", "name" => "directory_path", "options" => nil, "prompt" => nil, "required" => true, "type" => "populated_string", "value" => "/tmp/var/archive", "warning" => nil},
          {"default" => nil, "description" => "SFTP user name", "error" => nil, "group" => "sftp", "name" => "username", "options" => nil, "prompt" => "user", "required" => true, "type" => "populated_string", "value" => "invalid", "warning" => nil},
          {"default" => nil, "description" => "SFTP user password", "error" => nil, "group" => "sftp", "name" => "password", "options" => nil, "prompt" => "password", "required" => false, "type" => "encoded_string", "value" => nil, "warning" => nil},
          {"default" => nil, "description" => "SSH Key (not filename!) for SFTP connection", "error" => nil, "group" => "sftp", "name" => "key", "options" => nil, "prompt" => "password", "required" => false, "type" => "string", "value" => nil, "warning" => nil},
          {"default" => 5000, "description" => "Maximum number archives to store per subdirectory.", "error" => nil, "group" => "archive", "name" => "max_archives_per_dir", "options" => nil, "prompt" => nil, "required" => true, "type" => "positive_integer", "value" => 100, "warning" => nil},
        ]}

      assert_equal'Invalid archive config. test_connection: Unable to resolve host invalid.noragh.com.', failure_detail['message']
      assert_equal expected_markup, failure_detail['markup']
    end
  end

  def test_get_actions_defined
    get '/actions/defined.json' do
      assert last_response.ok?
      all_actions = JSON.parse( last_response.body )
      test_action = all_actions[ 'Collect' ].find{ |info_hash| info_hash['name'] == 'Armagh::StandardActions::TIAATestCollect' }
      assert_equal TEST_DESCRIPTION, test_action['description']
    end
  end

  def test_get_workflows
    good_alice_in_db
    expected_result = [{"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0, "valid"=>true}]

    get '/workflows.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  def test_get_workflow
    good_alice_in_db
    expected_result = {"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0, "valid"=>true}
    get '/workflow/alice/status.json' do
      result = JSON.parse(last_response.body)
      assert last_response.ok?
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_doesnt_exist
    good_alice_in_db
    get '/workflow/nope/status.json' do
      assert last_response.client_error?
      expected_result = {"client_error_detail"=>{"message"=>"Workflow nope not found", "markup"=>nil}}
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_run
    good_alice_in_db
    expect_alice_docs_in_db
    expected_result = {"name"=>"alice", "run_mode"=>"run", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41, "valid"=>true}
    patch '/workflow/alice/run.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_finish
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    expected_result = {"name"=>"alice", "run_mode"=>"finish", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41, "valid"=>true}
    patch '/workflow/alice/finish.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end

  end

  def test_get_workflow_finish_not_running
    good_alice_in_db
    expected_result = { 'client_error_detail' => { 'message' => 'Workflow not running', 'markup' => nil }}
    patch '/workflow/alice/finish.json' do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_stop
    good_alice_in_db
    expect_no_alice_docs_in_db
    @alice.run
    @alice.finish
    expected_result = {"name"=>"alice", "run_mode"=>"stop", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>0, "failed_docs_count"=>0, "published_pending_consume_docs_count"=>0, "docs_count"=>0, "valid"=>true}
    patch '/workflow/alice/stop.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  # NOTE:  If workflow is running and you send "stop", it's treated like you sent "finish"
  def test_get_workflow_stop_running
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    expected_result = {"name"=>"alice", "run_mode"=>"finish", "retired"=>false, "unused_output_docspec_check"=>false, "working_docs_count"=>29, "failed_docs_count"=>3, "published_pending_consume_docs_count"=>9, "docs_count"=>41, "valid"=>true}
    patch '/workflow/alice/stop.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_stop_documents_exist
    good_alice_in_db
    expect_alice_docs_in_db
    @alice.run
    @alice.finish
    expected_result = { 'client_error_detail' => { 'message' => 'Cannot stop - 41 documents still processing', 'markup' => nil }}
    patch '/workflow/alice/stop.json' do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      assert_equal expected_result, result
    end
  end

  private def read_workflow_fixture(*filenames)
    data = ''
    filenames.each do |filename|
      data.strip!
      data << ",\n  " unless data.empty?
      _data = File.read(File.expand_path('.', File.join('test', 'fixtures', filename)))
      _data.gsub!(/\n/, "\n  ") if filenames.size > 1
      data << _data
    end
    data.strip!
    filenames.size == 1 ? data : "[\n  #{data}\n]"
  end

  private def import_workflow_fixture(filename)
    post '/workflow/import.json', read_workflow_fixture(filename)
  end

  private def scrub_workflow_timestamp_and_versions(data)
    data.gsub!(/(\"workflow\": {\n\s+\"name\": \"\w+\",\n\s+\"exported\": ).+?(,\n\s+\"versions\": ).+?(,\n\s+\"actions\": \[)/m, '\1<timestamp>\2<versions>\3')
    data
  end

  def test_import_workflow
    import_workflow_fixture 'testflow.json'
    assert_equal(
      {"actions"=>["testflow-publish", "testflow-collect", "testflow-tacball"],
       "workflow"=>
        {"docs_count"=>0,
         "failed_docs_count"=>0,
         "name"=>"Testflow",
         "published_pending_consume_docs_count"=>0,
         "retired"=>false,
         "run_mode"=>"stop",
         "unused_output_docspec_check"=>true,
         "working_docs_count"=>0,
         "valid"=>true}},
      JSON.parse(last_response.body)
    )
    wf_set = Armagh::Actions::WorkflowSet.for_admin(Connection.config)
    assert_equal(
      [{'name'=>'Testflow', 'run_mode'=>'stop', 'retired'=>false, 'unused_output_docspec_check'=>true, 'working_docs_count'=>0, 'failed_docs_count'=>0, 'published_pending_consume_docs_count'=>0, 'docs_count'=>0, 'valid'=>true}],
      wf_set.list_workflows
    )
  end

  def test_export_workflow
    filename = 'newsflow.json'
    import_workflow_fixture(filename)
    get '/workflow/NEWSFLOW/export.json'
    assert_equal(
      scrub_workflow_timestamp_and_versions(read_workflow_fixture(filename)),
      scrub_workflow_timestamp_and_versions(JSON.parse(last_response.body))
    )
  end

  def test_export_workflows_all
    import_workflow_fixture('newsflow.json')
    import_workflow_fixture('testflow.json')
    get '/workflow/export.json'
    assert_equal(
      scrub_workflow_timestamp_and_versions(read_workflow_fixture('newsflow.json', 'testflow.json')),
      scrub_workflow_timestamp_and_versions(JSON.parse(last_response.body)),
    )
  end

  def test_get_workflow_actions_stopped
    good_alice_in_db
    db_time_approx = Time.now.to_f
    expected_residual_result = [{"active"=>false,
                                 "input_docspec"=>"__COLLECT__collect_alicedocs_from_source:ready",
                                 "name"=>"collect_alicedocs_from_source",
                                 "output_docspecs"=>["a_alicedoc:ready", "b_alicedocs_aggr_big:ready"],
                                 "supertype"=>"Armagh::Actions::Collect",
                                 "type"=>"Armagh::StandardActions::TWTestCollect",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_2",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"b_alicedoc:published",
                                 "output_docspecs"=>["b_aliceconsume_out_doc:ready"],
                                 "name"=>"consume_b_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"divide_b_alicedocs",
                                 "output_docspecs"=>["b_alicedocs_aggr:ready"],
                                 "supertype"=>"Armagh::Actions::Divide",
                                 "type"=>"Armagh::StandardActions::TWTestDivide",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"a_alicedoc:ready",
                                 "name"=>"publish_a_alicedocs",
                                 "output_docspecs"=>["a_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"b_alicedoc:ready",
                                 "name"=>"publish_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>false,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"split_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:ready"],
                                 "supertype"=>"Armagh::Actions::Split",
                                 "type"=>"Armagh::StandardActions::TWTestSplit",
                                 "valid"=>true}].sort{ |p1,p2| p1['name'] <=> p2['name']}

    get '/workflow/alice/actions.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      timestamps = []
      result.collect!{ |h| timestamps << Time.parse(h.delete( 'last_updated')); h}
      result.sort!{ |p1,p2| p1['name'] <=> p2['name']}

      assert_equal expected_residual_result.length, result.length

      expected_residual_result.each_with_index do |expected, idx|
        assert_equal expected, result[idx]
      end

      assert_in_delta db_time_approx, timestamps.min.to_f, 5
      assert_in_delta db_time_approx, timestamps.max.to_f, 5
    end
  end


  def test_get_workflow_actions_running
    good_alice_in_db
    @alice.run
    db_time_approx = Time.now.to_f
    expected_residual_result = [{"active"=>true,
                                 "input_docspec"=>"__COLLECT__collect_alicedocs_from_source:ready",
                                 "name"=>"collect_alicedocs_from_source",
                                 "output_docspecs"=>["a_alicedoc:ready", "b_alicedocs_aggr_big:ready"],
                                 "supertype"=>"Armagh::Actions::Collect",
                                 "type"=>"Armagh::StandardActions::TWTestCollect",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_2",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedoc:published",
                                 "output_docspecs"=>["b_aliceconsume_out_doc:ready"],
                                 "name"=>"consume_b_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"divide_b_alicedocs",
                                 "output_docspecs"=>["b_alicedocs_aggr:ready"],
                                 "supertype"=>"Armagh::Actions::Divide",
                                 "type"=>"Armagh::StandardActions::TWTestDivide",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:ready",
                                 "name"=>"publish_a_alicedocs",
                                 "output_docspecs"=>["a_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedoc:ready",
                                 "name"=>"publish_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"split_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:ready"],
                                 "supertype"=>"Armagh::Actions::Split",
                                 "type"=>"Armagh::StandardActions::TWTestSplit",
                                 "valid"=>true}].sort{ |p1,p2| p1['name'] <=> p2['name'] }

    get '/workflow/alice/actions.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      timestamps = []
      result.collect!{ |h| timestamps << Time.parse(h.delete( 'last_updated')); h}
      result.sort!{ |p1,p2| p1['name'] <=> p2['name']}

      assert_equal expected_residual_result.length, result.length

      expected_residual_result.each_with_index do |expected, idx|
        assert_equal expected, result[idx]
      end

      assert_in_delta db_time_approx, timestamps.min.to_f, 5
      assert_in_delta db_time_approx, timestamps.max.to_f, 5
    end

  end

  def test_get_workflow_actions_finishing
    good_alice_in_db
    @alice.run
    @alice.finish
    db_time_approx = Time.now.to_f
    expected_residual_result = [{"active"=>false,
                                 "input_docspec"=>"__COLLECT__collect_alicedocs_from_source:ready",
                                 "name"=>"collect_alicedocs_from_source",
                                 "output_docspecs"=>["a_alicedoc:ready", "b_alicedocs_aggr_big:ready"],
                                 "supertype"=>"Armagh::Actions::Collect",
                                 "type"=>"Armagh::StandardActions::TWTestCollect",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:published",
                                 "output_docspecs"=>["a_alicedoc_out:ready"],
                                 "name"=>"consume_a_alicedoc_2",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedoc:published",
                                 "output_docspecs"=>["b_aliceconsume_out_doc:ready"],
                                 "name"=>"consume_b_alicedoc_1",
                                 "supertype"=>"Armagh::Actions::Consume",
                                 "type"=>"Armagh::StandardActions::TWTestConsume",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"divide_b_alicedocs",
                                 "output_docspecs"=>["b_alicedocs_aggr:ready"],
                                 "supertype"=>"Armagh::Actions::Divide",
                                 "type"=>"Armagh::StandardActions::TWTestDivide",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"a_alicedoc:ready",
                                 "name"=>"publish_a_alicedocs",
                                 "output_docspecs"=>["a_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedoc:ready",
                                 "name"=>"publish_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:published"],
                                 "supertype"=>"Armagh::Actions::Publish",
                                 "type"=>"Armagh::StandardActions::TWTestPublish",
                                 "valid"=>true},
                                {"active"=>true,
                                 "input_docspec"=>"b_alicedocs_aggr_big:ready",
                                 "name"=>"split_b_alicedocs",
                                 "output_docspecs"=>["b_alicedoc:ready"],
                                 "supertype"=>"Armagh::Actions::Split",
                                 "type"=>"Armagh::StandardActions::TWTestSplit",
                                 "valid"=>true}].sort{ |p1,p2| p1['name'] <=> p2['name'] }

    get '/workflow/alice/actions.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      timestamps = []
      result.collect!{ |h| timestamps << Time.parse(h.delete( 'last_updated')); h}
      result.sort!{ |p1,p2| p1['name'] <=> p2['name']}

      assert_equal expected_residual_result.length, result.length

      expected_residual_result.each_with_index do |expected, idx|
        assert_equal expected, result[idx]
      end

      assert_in_delta db_time_approx, timestamps.min.to_f, 5
      assert_in_delta db_time_approx, timestamps.max.to_f, 5
    end

  end

  def test_get_workflow_actions_bad_alice
    good_alice_in_db
    Connection.config.find_one_and_update( { 'name' => 'collect_alicedocs_from_source' },
                                           { '$set' => { 'values.input.docspec' => '5' }} )
    db_time_approx = Time.now.to_f
    expected_residual_result = [
        {"active"=>false,
         "input_docspec"=>"",
         "name"=>"collect_alicedocs_from_source",
         "output_docspecs"=>["a_alicedoc:ready", "b_alicedocs_aggr_big:ready"],
         "supertype"=>"Armagh::Actions::Collect",
         "type"=>"Armagh::StandardActions::TWTestCollect",
         "valid"=>false},
        {"active"=>false,
         "input_docspec"=>"a_alicedoc:published",
         "output_docspecs"=>["a_alicedoc_out:ready"],
         "name"=>"consume_a_alicedoc_1",
         "supertype"=>"Armagh::Actions::Consume",
         "type"=>"Armagh::StandardActions::TWTestConsume",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"a_alicedoc:published",
         "output_docspecs"=>["a_alicedoc_out:ready"],
         "name"=>"consume_a_alicedoc_2",
         "supertype"=>"Armagh::Actions::Consume",
         "type"=>"Armagh::StandardActions::TWTestConsume",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"b_alicedoc:published",
         "output_docspecs"=>["b_aliceconsume_out_doc:ready"],
         "name"=>"consume_b_alicedoc_1",
         "supertype"=>"Armagh::Actions::Consume",
         "type"=>"Armagh::StandardActions::TWTestConsume",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"b_alicedocs_aggr_big:ready",
         "name"=>"divide_b_alicedocs",
         "output_docspecs"=>["b_alicedocs_aggr:ready"],
         "supertype"=>"Armagh::Actions::Divide",
         "type"=>"Armagh::StandardActions::TWTestDivide",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"a_alicedoc:ready",
         "name"=>"publish_a_alicedocs",
         "output_docspecs"=>["a_alicedoc:published"],
         "supertype"=>"Armagh::Actions::Publish",
         "type"=>"Armagh::StandardActions::TWTestPublish",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"b_alicedoc:ready",
         "name"=>"publish_b_alicedocs",
         "output_docspecs"=>["b_alicedoc:published"],
         "supertype"=>"Armagh::Actions::Publish",
         "type"=>"Armagh::StandardActions::TWTestPublish",
         "valid"=>true},
        {"active"=>false,
         "input_docspec"=>"b_alicedocs_aggr_big:ready",
         "name"=>"split_b_alicedocs",
         "output_docspecs"=>["b_alicedoc:ready"],
         "supertype"=>"Armagh::Actions::Split",
         "type"=>"Armagh::StandardActions::TWTestSplit",
         "valid"=>true}].sort{ |p1,p2| p1['name'] <=> p2['name']}

    get '/workflow/alice/actions.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      timestamps = []
      result.collect!{ |h|
        ts = h.delete('last_updated')
        timestamps << Time.parse(ts) unless ts.nil? || ts.empty?
        h
      }
      result.sort!{ |p1,p2| p1['name'] <=> p2['name']}

      assert_equal expected_residual_result.length, result.length

      expected_residual_result.each_with_index do |expected, idx|
        assert_equal expected, result[idx]
      end

      assert_in_delta db_time_approx, timestamps.min.to_f, 5
      assert_in_delta db_time_approx, timestamps.max.to_f, 5
    end
  end

  def test_get_workflow_action_status_bad_workflow
    good_alice_in_db
    get '/workflow/nope/action/nuhuh/status.json' do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      assert_equal( {"client_error_detail"=>{"message"=>"Workflow nope not found", "markup"=>nil}}, result)

    end
  end

  def test_get_workflow_action_status_bad_action
    good_alice_in_db
    get '/workflow/alice/action/nuhuh/status.json' do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      assert_equal( {"client_error_detail"=>{"message"=>"Workflow alice has no nuhuh action", "markup"=>nil}}, result)
    end
  end

  # gets a blank edit form for the action type
  def test_get_workflow_action_config
    good_alice_in_db
    get '/workflow/alice/action/config.json', {'type' => 'Armagh::StandardActions::TWTestCollect'} do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      expected_result = {
          'type' => 'Armagh::StandardActions::TWTestCollect',
          'supertype' => 'Armagh::Actions::Collect',
          'parameters' => [
              {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"alice", "options"=>nil},
              {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"extract", "description"=>"Extract incoming archive files", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"extract_format", "description"=>"The extraction mechanism to use.  Selecting auto will automatically determine the format based on incoming filename.", "type"=>"populated_string", "required"=>true, "default"=>"auto", "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>["auto", "7zip", "tar", "tgz", "zip"]},
              {"name"=>"extract_filter", "description"=>"Only extracted files matching this filter will be processed.  If not set, all files will be processed.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*.json", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>"__COLLECT__:ready", "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_state"=>"ready", "options"=>nil},
              {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil}
          ]}
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_action_config_invalid_workflow
    good_alice_in_db
    get '/workflow/fred/action/config.json', { 'type' => 'Armagh::StandardActions::Nope' } do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      expected_result = {"client_error_detail"=>{"message"=>"Workflow fred not found", "markup"=>nil}}
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_action_config_invalid_action_name
    good_alice_in_db
    get '/workflow/alice/action/config.json', { 'type' => 'Armagh::StandardActions::Nope' } do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      expected_result = {"client_error_detail"=>{"message"=>"Action class name Armagh::StandardActions::Nope not valid", "markup"=>nil}}
      assert_equal expected_result, result
    end
  end

  #edit form for existing action
  def test_get_workflow_description_existing_action
    good_alice_in_db
    get '/workflow/alice/action/collect_alicedocs_from_source/description.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      expected_result = {
          'type' => 'Armagh::StandardActions::TWTestCollect',
          'supertype' => 'Armagh::Actions::Collect',
          'parameters' => [
              {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_alicedocs_from_source", "options"=>nil},
              {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"alice", "options"=>nil},
              {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *", "options"=>nil},
              {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"extract", "description"=>"Extract incoming archive files", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"extract_format", "description"=>"The extraction mechanism to use.  Selecting auto will automatically determine the format based on incoming filename.", "type"=>"populated_string", "required"=>true, "default"=>"auto", "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"auto", "options"=>["auto", "7zip", "tar", "tgz", "zip"]},
              {"name"=>"extract_filter", "description"=>"Only extracted files matching this filter will be processed.  If not set, all files will be processed.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*.json", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>"__COLLECT__:ready", "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>"__COLLECT__collect_alicedocs_from_source:ready", "valid_state"=>"ready", "options"=>nil},
              {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>"a_alicedoc:ready", "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>"b_alicedocs_aggr_big:ready", "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6, "options"=>nil},
              {"group"=>"action", "error"=>nil},
              {"group"=>"collect", "error"=>nil}
          ]}
      assert_equal expected_result, result
    end
  end

  #can't get an edit form for an action unless the workflow is stopped
  def test_get_workflow_description_running
    good_alice_in_db
    @alice.run
    get '/workflow/alice/action/collect_alicedocs_from_source/description.json' do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      expected_result = {
          'type' => 'Armagh::StandardActions::TWTestCollect',
          'supertype' => 'Armagh::Actions::Collect',
          'parameters' => [
              {"name"=>"name", "description"=>"Name of this action configuration", "type"=>"populated_string", "required"=>true, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>CollectAction", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"collect_alicedocs_from_source", "options"=>nil},
              {"name"=>"active", "description"=>"Agents will run this configuration if active", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>true, "options"=>nil},
              {"name"=>"workflow", "description"=>"Workflow this action config belongs to", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"<WORKFLOW-NAME>", "group"=>"action", "warning"=>nil, "error"=>nil, "value"=>"alice", "options"=>nil},
              {"name"=>"schedule", "description"=>"Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*/15 * * * *", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"7 * * * *", "options"=>nil},
              {"name"=>"archive", "description"=>"Archive collected documents", "type"=>"boolean", "required"=>true, "default"=>true, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"decompress", "description"=>"Decompress (gunzip) incoming documents", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"extract", "description"=>"Extract incoming archive files", "type"=>"boolean", "required"=>true, "default"=>false, "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>false, "options"=>nil},
              {"name"=>"extract_format", "description"=>"The extraction mechanism to use.  Selecting auto will automatically determine the format based on incoming filename.", "type"=>"populated_string", "required"=>true, "default"=>"auto", "prompt"=>nil, "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>"auto", "options"=>["auto", "7zip", "tar", "tgz", "zip"]},
              {"name"=>"extract_filter", "description"=>"Only extracted files matching this filter will be processed.  If not set, all files will be processed.", "type"=>"populated_string", "required"=>false, "default"=>nil, "prompt"=>"*.json", "group"=>"collect", "warning"=>nil, "error"=>nil, "value"=>nil, "options"=>nil},
              {"name"=>"docspec", "description"=>"The type of document this action accepts", "type"=>"docspec", "required"=>true, "default"=>"__COLLECT__:ready", "prompt"=>nil, "group"=>"input", "warning"=>nil, "error"=>nil, "value"=>"__COLLECT__collect_alicedocs_from_source:ready", "valid_state"=>"ready", "options"=>nil},
              {"name"=>"docspec", "description"=>"The docspec of the default output from this action", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>"a_alicedoc:ready", "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"docspec2", "description"=>"collected documents of second type", "type"=>"docspec", "required"=>true, "default"=>nil, "prompt"=>nil, "group"=>"output", "warning"=>nil, "error"=>nil, "value"=>"b_alicedocs_aggr_big:ready", "valid_states"=>["ready", "working"], "options"=>nil},
              {"name"=>"count", "description"=>"desc", "type"=>"integer", "required"=>true, "default"=>6, "prompt"=>nil, "group"=>"tw_test_collect", "warning"=>nil, "error"=>nil, "value"=>6, "options"=>nil},
              {"group"=>"action", "error"=>nil},
              {"group"=>"collect", "error"=>nil}
          ]}
      assert_equal expected_result, result
    end
  end

  def test_get_workflow_config_existing_action
    good_alice_in_db
    get '/workflow/alice/action/collect_alicedocs_from_source/config.json' do
      assert last_response.ok?
      result = JSON.parse(last_response.body)
      expected_result = {
          'action' => {
              'name' => 'collect_alicedocs_from_source',
              'active' => 'false',
              'workflow' => 'alice'
          },
          'collect' => {
              'schedule' => '7 * * * *',
              'archive' => 'false',
              'decompress' => 'false',
              'extract' => 'false',
              'extract_format' => 'auto'
          },
          'input' => {
              'docspec' => '__COLLECT__collect_alicedocs_from_source:ready'
          },
          'output' => {
              'docspec' => 'a_alicedoc:ready',
              'docspec2' => 'b_alicedocs_aggr_big:ready'
          },
          'tw_test_collect' => {
              'count' => '6'
          },
          'type' => 'Armagh::StandardActions::TWTestCollect'
      }
      assert_equal expected_result, result
    end
  end

  #submit a form to create a NEW action
  def test_post_workflow_action_config
    good_alice_in_db
    consume_values = Armagh::StandardActions::TWTestConsume.make_config_values(
        action_name: 'new_alice_consume', input_doctype: 'alicedoc', output_doctype: 'alicedoc_out' )
    fields = consume_values.merge({ 'type' => 'Armagh::StandardActions::TWTestConsume'})

    post '/workflow/alice/action/config.json', fields.to_json  do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      result['parameters'].sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      expected_result = {
          'type' => 'Armagh::StandardActions::TWTestConsume',
          'supertype' => 'Armagh::Actions::Consume',
          'parameters' =>[
              {"default"=>nil, "description"=>"Name of this action configuration", "error"=>nil, "group"=>"action", "name"=>"name", "prompt"=>"<WORKFLOW-NAME>CollectAction", "required"=>true, "type"=>"populated_string", "value"=>"new_alice_consume", "warning"=>nil, "options"=>nil},
              {"default"=>false, "description"=>"Agents will run this configuration if active", "error"=>nil, "group"=>"action", "name"=>"active", "prompt"=>nil, "required"=>true, "type"=>"boolean", "value"=>false, "warning"=>nil, "options"=>nil},
              {"default"=>nil, "description"=>"Workflow this action config belongs to", "error"=>nil, "group"=>"action", "name"=>"workflow", "prompt"=>"<WORKFLOW-NAME>", "required"=>false, "type"=>"populated_string", "value"=>"alice", "warning"=>nil, "options"=>nil},
              {"default"=>nil, "description"=>"Input doctype for this action", "error"=>nil, "group"=>"input", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>"alicedoc:published", "warning"=>nil, "valid_state"=>"published", "options"=>nil},
              {"default"=>nil, "description"=>"the output from consume", "error"=>nil, "group"=>"output", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "valid_states"=>[nil, "ready", "working"], "value"=>"alicedoc_out:ready", "warning"=>nil, "options"=>nil},
              {"error"=>nil, "group"=>"action"},
              {"error"=>nil, "group"=>"consume"}
          ].sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      }

      assert_equal expected_result, result
    end
  end

  def test_post_workflow_action_config_bad_config
    good_alice_in_db
    consume_values = Armagh::StandardActions::TWTestConsume.make_config_values(
        action_name: 'new_alice_consume', input_doctype: 'alicedoc', output_doctype: 'alicedoc_out' )
    fields = consume_values.merge({ 'type' => 'Armagh::StandardActions::TWTestConsume'})
    fields['input'].delete 'docspec'

    post '/workflow/alice/action/config.json', fields.to_json  do
      assert last_response.client_error?
      result = JSON.parse( last_response.body ).sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      expected_result = { 'client_error_detail' => {
          'markup' => {
              'type' => 'Armagh::StandardActions::TWTestConsume',
              'supertype' => 'Armagh::Actions::Consume',
              'parameters' => [
                  {"default"=>nil, "description"=>"Name of this action configuration", "error"=>nil, "group"=>"action", "name"=>"name", "prompt"=>"<WORKFLOW-NAME>CollectAction", "required"=>true, "type"=>"populated_string", "value"=>"new_alice_consume", "warning"=>nil, "options"=>nil},
                  {"default"=>false, "description"=>"Agents will run this configuration if active", "error"=>nil, "group"=>"action", "name"=>"active", "prompt"=>nil, "required"=>true, "type"=>"boolean", "value"=>false, "warning"=>nil, "options"=>nil},
                  {"default"=>nil, "description"=>"Workflow this action config belongs to", "error"=>nil, "group"=>"action", "name"=>"workflow", "prompt"=>"<WORKFLOW-NAME>", "required"=>false, "type"=>"populated_string", "value"=>"alice", "warning"=>nil, "options"=>nil},
                  {"default"=>nil, "description"=>"Input doctype for this action", "error"=>"type validation failed: value cannot be nil", "group"=>"input", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>nil, "warning"=>nil, "options"=>nil},
                  {"default"=>nil, "description"=>"the output from consume", "error"=>nil, "group"=>"output", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>"alicedoc_out:ready", "warning"=>nil, "options"=>nil},
              ]},
          'message' => "Configuration has errors: Unable to create configuration for 'Armagh::StandardActions::TWTestConsume' named 'new_alice_consume' because: \n    Group 'input' Parameter 'docspec': type validation failed: value cannot be nil"
      }}.sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      assert_equal expected_result, result
    end
  end

  def test_post_workflow_action_config_running
    good_alice_in_db
    @alice.run
    consume_values = Armagh::StandardActions::TWTestConsume.make_config_values(
        action_name: 'new_alice_consume', input_doctype: 'alicedoc', output_doctype: 'alicedoc_out' )
    fields = consume_values.merge({ 'type' => 'Armagh::StandardActions::TWTestConsume'})

    post '/workflow/alice/action/config.json', fields.to_json  do
      assert last_response.client_error?
      result = JSON.parse( last_response.body )
      expected_result = {"client_error_detail"=>{"message"=>"Stop workflow before making changes", "markup"=>nil}}
      assert_equal expected_result, result
    end
  end

  #submit a form to update an EXISTING action
  def test_put_workflow_action_config_existing
    good_alice_in_db
    new_values = {
        'action' => { 'name' => 'collect_alicedocs_from_source' },
        'collect' => { 'schedule' => '29 * * * *', 'archive' => false },
        'input'  => {},
        'output' => {
            'docspec' => Armagh::Documents::DocSpec.new( 'new_a_docs', 'ready' ),
            'docspec2' => Armagh::Documents::DocSpec.new( 'new_b_docs', 'ready' )
        }
    }

    put '/workflow/alice/action/collect_alicedocs_from_source/config.json', new_values.to_json  do
      assert last_response.ok?
      result = JSON.parse( last_response.body )
      result['parameters'].sort!{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      expected_result = {
          'type' => 'Armagh::StandardActions::TWTestCollect',
          'supertype' => 'Armagh::Actions::Collect',
          'parameters' => [{"error" => nil, "group" => "action"},
                           {"default" => false, "description" => "Agents will run this configuration if active", "error" => nil, "group" => "action", "name" => "active", "prompt" => nil, "required" => true, "type" => "boolean", "value" => false, "warning" => nil, "options" => nil},
                           {"default" => nil, "description" => "Name of this action configuration", "error" => nil, "group" => "action", "name" => "name", "prompt" => "<WORKFLOW-NAME>CollectAction", "required" => true, "type" => "populated_string", "value" => "collect_alicedocs_from_source", "warning" => nil, "options" => nil},
                           {"default" => nil, "description" => "Workflow this action config belongs to", "error" => nil, "group" => "action", "name" => "workflow", "prompt" => "<WORKFLOW-NAME>", "required" => false, "type" => "populated_string", "value" => "alice", "warning" => nil, "options" => nil},
                           {"error" => nil, "group" => "collect"},
                           {"default" => true, "description" => "Archive collected documents", "error" => nil, "group" => "collect", "name" => "archive", "prompt" => nil, "required" => true, "type" => "boolean", "value" => false, "warning" => nil, "options" => nil},
                           {"default" => false, "description" => "Decompress (gunzip) incoming documents", "error" => nil, "group" => "collect", "name" => "decompress", "options" => nil, "prompt" => nil, "required" => true, "type" => "boolean", "value" => false, "warning" => nil},
                           {"default" => false, "description" => "Extract incoming archive files", "error" => nil, "group" => "collect", "name" => "extract", "options" => nil, "prompt" => nil, "required" => true, "type" => "boolean", "value" => false, "warning" => nil},
                           {"default" => nil, "description" => "Only extracted files matching this filter will be processed.  If not set, all files will be processed.", "error" => nil, "group" => "collect", "name" => "extract_filter", "options" => nil, "prompt" => "*.json", "required" => false, "type" => "populated_string", "value" => nil, "warning" => nil},
                           {"default"=>"auto", "description"=> "The extraction mechanism to use.  Selecting auto will automatically determine the format based on incoming filename.", "error"=>nil, "group"=>"collect", "name"=>"extract_format", "options"=>["auto", "7zip", "tar", "tgz", "zip"], "prompt"=>nil, "required"=>true, "type"=>"populated_string", "value"=>"auto", "warning"=>nil},
                           {"default" => nil, "description" => "Schedule to run the collector.  Cron syntax.  If not set, Collect must be manually triggered.", "error" => nil, "group" => "collect", "name" => "schedule", "prompt" => "*/15 * * * *", "required" => false, "type" => "populated_string", "value" => "29 * * * *", "warning" => nil, "options" => nil},
                           {"default"=>"__COLLECT__:ready", "description"=>"The type of document this action accepts", "error"=>nil, "group"=>"input", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>"__COLLECT__:ready", "warning"=>nil, "valid_state"=>"ready", "options"=>nil},
                           {"default"=>nil, "description"=>"The docspec of the default output from this action", "error"=>nil, "group"=>"output", "name"=>"docspec", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>"new_a_docs:ready", "warning"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
                           {"default"=>nil, "description"=>"collected documents of second type", "error"=>nil, "group"=>"output", "name"=>"docspec2", "prompt"=>nil, "required"=>true, "type"=>"docspec", "value"=>"new_b_docs:ready", "warning"=>nil, "valid_states"=>["ready", "working"], "options"=>nil},
                           {"default"=>6, "description"=>"desc", "error"=>nil, "group"=>"tw_test_collect", "name"=>"count", "prompt"=>nil, "required"=>true, "type"=>"integer", "value"=>6, "warning"=>nil, "options"=>nil}
          ].sort{ |p1,p2| "#{p1['group']}:#{p1['name']}" <=> "#{p2['group']}:#{p2['name']}"}
      }
      assert_equal expected_result, result
    end
  end

  def test_get_documents
    type = 'TestType'
    @api.expects(:user_has_document_role)
    get '/documents.json', {type: type} do
      assert last_response.ok?
      assert_empty JSON.parse(last_response.body)
    end

    @api.unstub(:user_has_document_role)
    doc = Armagh::Document.create(type: type, content: { 'text' => 'bogusness' }, raw: 'raw', metadata: {},
                                  pending_actions: [], state: Armagh::Documents::DocState::PUBLISHED, document_id: 'test-id',
                                  collection_task_ids: [ '123' ], document_timestamp: Time.now, title: 'Test Document' )

    get '/documents.json', {type: type} do
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
    @api.expects(:user_has_document_role)
    @api.expects(:get_documents).raises(e)
    get '/documents.json', {type: 'type'} do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('server_error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('server_error_detail', 'message'))
    end
  end

  def test_get_documents_missing_params
    get '/documents.json', {} do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'type' is missing but is required.", response.dig('client_error_detail', 'message')
    end
  end

  def test_get_document
    get '/document.json' do
      assert last_response.client_error?
      response =  JSON.parse(last_response.body)
      assert_equal("A parameter named 'id' is missing but is required.", response.dig('client_error_detail', 'message'))
    end

    doc = Armagh::Document.create(type: 'TestType', content: { 'text' => 'bogusness' }, raw: 'raw', metadata: {},
                                  pending_actions: [], state: Armagh::Documents::DocState::PUBLISHED, document_id: 'test-id',
                                  collection_task_ids: [ '123' ], document_timestamp: Time.now, title: 'Test Document' )
    doc.save

    get '/document.json', {type: doc.type, id: doc.document_id} do
      assert last_response.ok?
      found_doc = JSON.parse(last_response.body)
      assert_equal doc.document_id, found_doc['document_id']
      assert_equal doc.title, found_doc['title']
    end
  end

  def test_get_document_error
    e = RuntimeError.new('Bad')
    @api.expects(:user_has_document_role)
    @api.expects(:get_document).raises(e)
    get '/document.json', {type: 'type', id: 'id'} do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.class.to_s, response_hash.dig('server_error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('server_error_detail', 'message'))
    end
  end

  def test_get_document_missing_params
    get '/document.json', {'id' => 'something'} do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'type' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get '/document.json', {'type' => 'something'} do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'id' is missing but is required.", response.dig('client_error_detail', 'message')
    end
  end

  def test_document_failures
    count = 10
    count.times do |i|
      doc = Armagh::Document.create(type: 'TestType', content: { 'text' => 'bogusness' }, raw: 'raw', metadata: {},
                                    pending_actions: [], state: Armagh::Documents::DocState::READY, document_id: "id_#{i}",
                                    collection_task_ids: [ '123' ], document_timestamp: Time.now )
      doc.add_error_to_dev_errors('test_action', 'details')
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
      assert_equal(e.class.to_s, response_hash.dig('server_error_detail', 'class'))
      assert_equal(e.message, response_hash.dig('server_error_detail', 'message'))
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

  def test_trigger_collect
    good_alice_in_db
    @alice.run

    patch '/actions/trigger_collect.json', {name: 'collect_alicedocs_from_source'} do
      assert last_response.ok?
      assert_equal true, JSON.parse(last_response.body)
    end
  end

  def test_trigger_collect_bad_action
    patch '/actions/trigger_collect.json', {name: 'not_real'} do
      assert last_response.client_error?
      response_hash = JSON.parse(last_response.body)
      message = response_hash.dig('client_error_detail', 'message')
      assert_equal('Action not_real is not an active action.', message)
    end
  end

  def test_trigger_collect_error
    e = RuntimeError.new('Bad')
    @api.expects(:trigger_collect).raises(e)

    patch '/actions/trigger_collect.json', {name: 'not_real'} do
      assert last_response.server_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal(e.message, response_hash.dig('server_error_detail', 'message'))
    end
  end

  def test_trigger_collect_no_name
    patch '/actions/trigger_collect.json' do
      assert last_response.client_error?
      response_hash = JSON.parse(last_response.body)
      assert_equal 'No action name supplied.', response_hash.dig('client_error_detail', 'message')
    end
  end

  def test_users
    initial_user_length = Armagh::Authentication::User.find_all.length
    Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com')
    get '/users.json' do
      assert last_response.ok?
      response = JSON.parse(last_response.body)
      assert_equal initial_user_length + 1, response.length
      result = response.last
      assert_kind_of(String, result['id'])
      assert_equal('testuser',result['username'])
      assert_equal('Test User',result['name'])
      assert_equal('test@user.com',result['email'])
      assert_equal(Armagh::Authentication::User.find_all.last.to_json, result.to_json)
    end
  end

  def test_user_admin
    user_id = nil
    user = {
        'username' => 'testuser',
        'password' => 'SomeSuperPassword',
        'email' => 'user@users.com',
        'name' => 'Test User'
    }

    # Create
    post '/user/create.json', user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('Test User', response['name'])
      assert_equal('user@users.com', response['email'])
      assert_equal('testuser', response['username'])
      user_id = response['id']
      assert_not_nil user_id
    end

    # Create duplicate
    post '/user/create.json', user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A user with username 'testuser' already exists.", response.dig('client_error_detail', 'message')
    end

    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('Test User', response['name'])
      assert_equal('user@users.com', response['email'])
      assert_equal('testuser', response['username'])
    end

    # Update
    user['name'] = 'Tester'
    user.delete 'password'
    put "/user/#{user_id}.json", user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('Tester', response['name'])
      assert_equal('user@users.com', response['email'])
      assert_equal('testuser', response['username'])
    end

    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('Tester', response['name'])
      assert_equal('user@users.com', response['email'])
      assert_equal('testuser', response['username'])
      assert_empty response['roles']
    end

    # Roles
    get "/user/#{user_id}/add_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      response = JSON.parse(last_response.body)
      assert_true response
    end

    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([Armagh::Authentication::Role::USER.key], response['roles'])
    end

    get "/user/#{user_id}/remove_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['roles']
    end

    get "/user/#{user_id}/remove_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("User 'testuser' does not have a direct role of 'doc_user'.", response.dig('client_error_detail', 'message'))
    end

    # bad name
    put "/user/#{user_id}.json", user.merge({'name' => nil}).to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal('Name must be a nonempty string.', response.dig('client_error_detail', 'message'))
    end

    # bad email
    put "/user/#{user_id}.json", user.merge({'email' => nil}).to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal('Email must be a nonempty string.', response.dig('client_error_detail', 'message'))
    end

    # users
    get '/users.json' do
      assert last_response.ok?
      JSON.parse(last_response.body)

      assert_equal 'testuser', user['username']
    end

    # Make sure user is unlocked
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_false response['locked']
      assert_false response['disabled']
    end

    # Lock
    get "/user/#{user_id}/lock.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    # Make sure user is locked
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response['locked']
      assert_false response['disabled']
    end

    # Unlock
    get "/user/#{user_id}/unlock.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    # Make sure user is unlocked & not enabled
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_false response['locked']
      assert_false response['disabled']
    end

    # Disable
    get "/user/#{user_id}/disable.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    # Make sure user is unlocked & not enabled
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_false response['locked']
      assert_true response['disabled']
    end

    # Enable
    get "/user/#{user_id}/enable.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    # Make sure user is unlocked & enabled
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_false response['locked']
      assert_false response['disabled']
    end

    # Reset Password
    get "/user/#{user_id}/reset_password.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_kind_of(String, response)
      assert_true response.length >= Armagh::Authentication.config.authentication.min_password_length
    end

    # delete
    delete("/user/#{user_id}.json") {
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    }

    delete "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("User with ID #{user_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # Get - make sure it's gone
    get "/user/#{user_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("User with ID #{user_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # update doesnt exist
    put "/user/#{user_id}.json", user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("User with ID #{user_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # Missing params
    get("/user/#{user_id}/join_group.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'group_id' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/user/#{user_id}/leave_group.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'group_id' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/user/#{user_id}/add_role.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'role_key' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/user/#{user_id}/remove_role.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'role_key' is missing but is required.", response.dig('client_error_detail', 'message')
    end
  end

  def test_groups
    initial_group_length = Armagh::Authentication::Group.find_all.length
    Armagh::Authentication::Group.create(name: 'testgroup', description: 'Test Group')
    get '/groups.json' do
      assert last_response.ok?
      response = JSON.parse(last_response.body)
      assert_equal initial_group_length + 1, response.length
      result = response.last
      assert_equal('testgroup',result['name'])
      assert_equal('Test Group', result['description'])
      assert_equal(Armagh::Authentication::Group.find_all.last.to_json, result.to_json)
    end
  end

  def test_group
    group_id = nil
    group = {
        'name' => 'testgroup',
        'description' => 'Test Group'
    }

    # Create
    post '/group/create.json', group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('testgroup', response['name'])
      assert_equal('Test Group', response['description'])
      group_id = response['id']
      assert_not_nil group_id
    end

    # Create duplicate
    post '/group/create.json', group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A group with name 'testgroup' already exists.", response.dig('client_error_detail', 'message')
    end

    get "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('testgroup', response['name'])
      assert_equal('Test Group', response['description'])
    end

    # Update
    group['description'] = 'New Description'
    put "/group/#{group_id}.json", group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('New Description', response['description'])
      assert_equal('testgroup', response['name'])
    end

    get "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal('New Description', response['description'])
      assert_equal('testgroup', response['name'])
      assert_empty response['roles']
    end

    # Roles
    get "/group/#{group_id}/add_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([Armagh::Authentication::Role::USER.key], response['roles'])
    end

    get "/group/#{group_id}/remove_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['roles']
    end

    get "/group/#{group_id}/remove_role.json", {'role_key' => Armagh::Authentication::Role::USER.key} do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("Group 'testgroup' does not have a direct role of 'doc_user'.", response.dig('client_error_detail', 'message'))
    end

    # bad description
    put "/group/#{group_id}.json", group.merge({'description' => nil}).to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal('Description must be a nonempty string.', response.dig('client_error_detail', 'message'))
    end

    # groups
    get '/groups.json' do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      group =  response.first
      assert_include response.collect{|g|g['name']}, 'testgroup'
    end

    # delete
    delete "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    delete "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("Group with ID #{group_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # Get - make sure it's gone
    get "/group/#{group_id}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("Group with ID #{group_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # update doesnt exist
    put "/group/#{group_id}.json", group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal("Group with ID #{group_id} not found.", response.dig('client_error_detail', 'message'))
    end

    # Missing params
    get("/group/#{group_id}/add_user.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'user_id' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/group/#{group_id}/remove_user.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'user_id' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/group/#{group_id}/add_role.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'role_key' is missing but is required.", response.dig('client_error_detail', 'message')
    end

    get("/group/#{group_id}/remove_role.json", {}) do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?, response.to_s
      assert_equal "A parameter named 'role_key' is missing but is required.", response.dig('client_error_detail', 'message')
    end
  end

  def test_group_from_user
    user = {
        'username' => 'testuser',
        'password' => 'SomeSuperPassword',
        'email' => 'user@users.com',
        'name' => 'Test User'
    }

    group = {
        'name' => 'testgroup',
        'description' => 'Test Group'
    }

    groupid = nil
    userid = nil

    post '/group/create.json', group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty(response['users'])
      groupid = response['id']
    end

    post '/user/create.json', user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty(response['groups'])
      userid = response['id']
    end

    get("/user/#{userid}/join_group.json", {'group_id' => groupid}) {
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    }

    get "/group/#{groupid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([userid],response['users'])
    end

    get "/user/#{userid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([groupid], response['groups'])
    end

    get "/user/#{userid}/leave_group.json", {'group_id' => groupid} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/group/#{groupid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['users']
    end

    get "/user/#{userid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['groups']
    end
  end

  def test_user_from_group
    user = {
        'username' => 'testuser',
        'password' => 'SomeSuperPassword',
        'email' => 'user@users.com',
        'name' => 'Test User'
    }

    group = {
        'name' => 'testgroup',
        'description' => 'Test Group'
    }

    groupid = nil
    userid = nil

    post '/group/create.json', group.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty(response['users'])
      groupid = response['id']
    end

    post '/user/create.json', user.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty(response['groups'])
      userid = response['id']
    end

    get "/group/#{groupid}/add_user.json", {'user_id' => userid} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/group/#{groupid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([userid],response['users'])
    end

    get "/user/#{userid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_equal([groupid], response['groups'])
    end

    get "/group/#{groupid}/remove_user.json", {'user_id' => userid} do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_true response
    end

    get "/group/#{groupid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['users']
    end

    get "/user/#{userid}.json" do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, response.to_s
      assert_empty response['groups']
    end
  end

  def test_roles
    get '/roles.json' do
      assert last_response.ok?
      response = JSON.parse(last_response.body)

      expected = []
      Armagh::Authentication::Role::PREDEFINED_ROLES.each do |role|
        expected << role.to_hash
      end

      assert_equal(expected, response)
    end
  end

  def test_authenticate
    expected = {
      'auth_failures' => 0,
      'disabled' => false,
      'username' => @test_username
    }

    get '/authenticate.json' do
      response = JSON.parse(last_response.body)
      assert last_response.ok?
      thin_response = response.keep_if{|k, _v| expected.keys.include?(k)}
      assert_equal expected, thin_response
    end
  end

  def test_user
    expected = {
      'username' => @test_username,
      'name' => 'Super Admin',
      'email' => 'superadmin@example.com'
    }

    get '/user.json' do
      response = JSON.parse(last_response.body)
      assert last_response.ok?
      assert_nil response['password']
      assert_nil response['hashed_password']
      thin_response = response.keep_if{|k, _v| expected.keys.include?(k)}
      assert_equal expected, thin_response
    end

    # Change Name and password
    changed = expected.dup
    changed['name'] = 'New Name'
    changed['password'] = 'newpassword'
    put '/user.json', changed.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?
      assert_nil response['password']
      assert_nil response['hashed_password']
      changed.delete('password')
      thin_response = response.keep_if{|k, _v| changed.keys.include?(k)}
      assert_equal changed, thin_response
    end

    get '/user.json' do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal("Authentication failed for #{@test_username}.", response.dig('authentication_error_detail', 'message'))
    end

    authorize @test_username, 'newpassword'
    get '/user.json' do
      response = JSON.parse(last_response.body)
      assert last_response.ok?
      assert_nil response['password']
      assert_nil response['hashed_password']
      thin_response = response.keep_if{|k, _v| changed.keys.include?(k)}
      assert_equal changed, thin_response
    end

    authorize @test_username, 'invalid_password'
    put '/user.json' do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal("Authentication failed for #{@test_username}.", response.dig('authentication_error_detail', 'message'))
    end

    authorize 'invalid_user', @test_password
    put '/user.json' do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal('Authentication failed for invalid_user.', response.dig('authentication_error_detail', 'message'))
    end
  end

  def test_update_password
    post '/update_password.json', {}.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal("A parameter named 'password' is missing but is required.", response.dig('client_error_detail', 'message'))
    end

    post '/update_password.json', {'password' => '(@u3jidJ*#JDHH@@!'}.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.ok?
      assert_true response
    end

    # Should fail because password was changed
    post '/update_password.json', {'password' => '(!!!@u3jidJ*#JDHH@@!'}.to_json do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal("Authentication failed for #{@test_username}.", response.dig('authentication_error_detail', 'message'))
    end

    authorize @test_username, 'invalid password'
    post '/update_password.json' do
      response = JSON.parse(last_response.body)
      assert last_response.client_error?
      assert_equal("Authentication failed for #{@test_username}.", response.dig('authentication_error_detail', 'message'))
    end

  end

  def test_role_permissions
    users = users_with_all_roles
    endpoints = {
        lambda{get('/status.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{post("/configuration/launcher/#{Launcher.config_name}.json"){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{post('/configuration/agent.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflows.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{post('/workflow/:workflow_name/new.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/status.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{patch('/workflow/:workflow_name/run.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{patch('/workflow/:workflow_name/finish.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{patch('/workflow/:workflow_name/stop.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/actions/defined.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{patch('/actions/trigger_collect.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/actions.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/action/:action_name/status.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/action/config.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/action/:action_name/description.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/workflow/:workflow_name/action/:action_name/config.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{post('/workflow/:workflow_name/action/config.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{put('/workflow/:workflow_name/action/:action_name/config.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/test/:type/callbacks.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{patch('/test/invoke_callback.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/documents.json', {type: 'type'}){}} => Authentication::Role::USER,
        lambda{get('/document.json', {type: 'type', id: '123'}){}} => Authentication::Role::USER,
        lambda{get('/documents/failures.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/version.json'){}} => Authentication::Role::APPLICATION_ADMIN,
        lambda{get('/users.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{put('/user/:user_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{post('/user/create.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/join_group.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/leave_group.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/add_role.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/remove_role.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{delete('/user/:user_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/reset_password.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/lock.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/unlock.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/enable.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/user/:user_id/disable.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/groups.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/group/:group_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{put('/group/:group_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/group/:group_id/add_user.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/group/:group_id/remove_user.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{post('/group/create.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/group/:group_id/add_role.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/group/:group_id/remove_role.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{delete('/group/:group_id.json'){}} => Authentication::Role::USER_ADMIN,
        lambda{get('/roles.json'){}} => Authentication::Role::USER_ADMIN
    }

    endpoints.each do |lam, role|
      users.each do |user_role, user|
        username = user.username
        password = user.username.sub('user', 'password')
        authorize username, password

        file, line = lam.source_location
        lam_src = File.readlines(file)[line-1].strip

        if role == user_role
          lam.call
          response = assert_nothing_raised("An unparsable response was returned for #{username} from #{lam_src}: #{last_response.body}") {JSON.parse(last_response.body)}
          if response.is_a? Hash
            assert_false response.key?('authentication_error_detail'), "An unexpected authentication error was returned for #{username} from #{lam_src}"
          end
        else
          lam.call
          response = JSON.parse(last_response.body)
          assert_true response.key?('authentication_error_detail'), "No authentication error was returned for #{username} from #{lam_src}"
        end
      end
    end
  end

  def test_user_permissions
    user1 = Authentication::User.create(username: 'user1',
                                       password: 'password_1',
                                       name: 'test user',
                                       email: 'user@example.com')

    user2 = Authentication::User.create(username: 'user2',
                                       password: 'password_2',
                                       name: 'test user',
                                       email: 'user@example.com')

    authorize 'user1', 'password_1'
    get("/user/#{user1.internal_id}.json") do
      response = JSON.parse(last_response.body)
      assert last_response.ok?, "User 1 cannot get their own details: #{response}"
    end

    get("/user/#{user2.internal_id}.json") do
      response = JSON.parse(last_response.body)
      assert_true response.key?('authentication_error_detail'), "User 1 can get User 2 details: #{response}"
    end

    endpoints = [
      lambda{get('/authenticate.json'){}},
      lambda{get('/user.json'){}},
    ]

    endpoints.each do |lam|
      file, line = lam.source_location
      lam_src = File.readlines(file)[line-1].strip

      authorize 'user1', 'password_1'
      lam.call do
        response = JSON.parse(last_response.body)
        assert last_response.ok?, "Error in #{lam_src} with user1"
        assert_equal 'user1', response['username']
      end

      authorize 'user2', 'password_2'
      lam.call
      response = JSON.parse(last_response.body)
      assert last_response.ok?, "Error in #{lam_src} with user1"
      assert_equal 'user2', response['username']

      authorize 'user1', 'badpassword'
      lam.call
      assert last_response.client_error?, "Error in #{lam_src} incorrect password"
    end
  end
end
