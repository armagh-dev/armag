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

require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../helpers/coverage_helper'
require_relative '../../../../lib/armagh/admin/application/admin_gui'

module Armagh
  module Admin
    module Application
      class TestAdminGUI < Test::Unit::TestCase

        def setup
          HTTPClient.any_instance.stubs(:set_auth)
          @admin_gui = AdminGUI.instance
        end

        def test_private_get_json
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns({'message'=>'stuff'}.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          result = @admin_gui.send(:get_json, 'ok.url')
          assert_equal 'stuff', result
        end

        def test_private_get_json_error
          response = mock('response')
          response.stubs(:status).returns(400)
          response.stubs(:reason).returns('some reason')
          response.stubs(:body).returns({'client_error_detail'=>{'message'=>'some error'}}.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          e = assert_raise AdminGUIHTTPError do
            @admin_gui.send(:get_json, 'error.url')
          end
          assert_equal 'some error', e.message
        end

        def test_private_get_json_http_404
          response = mock('response')
          response.stubs(:status).returns(404)
          response.stubs(:reason).returns('not found')
          response.stubs(:body).returns('whatever')
          HTTPClient.any_instance.expects(:get).once.returns(response)
          e = assert_raise AdminGUIHTTPError do
            @admin_gui.send(:get_json, 'missing.url')
          end
          assert_equal 'API HTTP get request to http://127.0.0.1:4599/missing.url failed with status 404 not found', e.message
        end

        def test_private_get_json_with_status
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns({'message'=>'stuff'}.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          result = @admin_gui.send(:get_json_with_status, 'ok.url')
          assert_equal [:success, 'stuff'], result
        end

        def test_private_post_json
          data = {'field'=>'value'}
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns(data.to_json)
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'ok.url')
          assert_equal [:success, 'value'], result
        end

        def test_private_post_json_error
          response = mock('response')
          response.stubs(:status).returns(400)
          data = 'some error'
          response.stubs(:body).returns({'client_error_detail'=>data}.to_json)
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'error.url')
          assert_equal [:error, data], result
        end

        def test_private_post_json_http_404
          response = mock('response')
          response.stubs(:status).returns(404)
          response.stubs(:reason).returns('not found')
          response.stubs(:body).returns('body')
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'missing.url')
          expected = 'API HTTP post request to http://127.0.0.1:4599/missing.url failed with status 404 not found'
          assert_equal [:error, expected], result
        end

        def test_private_put_json
          data = {'field'=>'value'}
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns(data.to_json)
          HTTPClient.any_instance.expects(:put).once.returns(response)
          result = @admin_gui.send(:put_json, 'ok.url')
          assert_equal [:success, 'value'], result
        end

        def test_private_put_json_error
          response = mock('response')
          response.stubs(:status).returns(400)
          data = 'some error'
          response.stubs(:body).returns({'client_error_detail'=>data}.to_json)
          HTTPClient.any_instance.expects(:put).once.returns(response)
          result = @admin_gui.send(:put_json, 'error.url')
          assert_equal [:error, data], result
        end

        def test_private_put_json_http_404
          response = mock('response')
          response.stubs(:status).returns(404)
          response.stubs(:reason).returns('not found')
          response.stubs(:body).returns('body')
          HTTPClient.any_instance.expects(:put).once.returns(response)
          result = @admin_gui.send(:put_json, 'missing.url')
          expected = 'API HTTP put request to http://127.0.0.1:4599/missing.url failed with status 404 not found'
          assert_equal [:error, expected], result
        end

        def test_private_patch_json
          data = {'field'=>'value'}
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns(data.to_json)
          HTTPClient.any_instance.expects(:patch).once.returns(response)
          result = @admin_gui.send(:patch_json, 'ok.url')
          assert_equal [:success, 'value'], result
        end

        def test_private_patch_json_error
          response = mock('response')
          response.stubs(:status).returns(400)
          data = 'some error'
          response.stubs(:body).returns({'client_error_detail'=>data}.to_json)
          HTTPClient.any_instance.expects(:patch).once.returns(response)
          result = @admin_gui.send(:patch_json, 'error.url')
          assert_equal [:error, data], result
        end

        def test_private_patch_json_http_404
          response = mock('response')
          response.stubs(:status).returns(404)
          response.stubs(:reason).returns('not found')
          response.stubs(:body).returns('body')
          HTTPClient.any_instance.expects(:patch).once.returns(response)
          result = @admin_gui.send(:patch_json, 'missing.url')
          expected = 'API HTTP patch request to http://127.0.0.1:4599/missing.url failed with status 404 not found'
          assert_equal [:error, expected], result
        end

        def test_private_http_request_json_parse_error
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:reason).returns('ok')
          response.stubs(:body).returns('this is not json')
          http = mock('http')
          http.stubs(:set_auth)
          HTTPClient.any_instance.stubs(:new).returns(http)
          HTTPClient.any_instance.stubs(:get).returns(response)
          result = @admin_gui.send(:get_json, 'fake.url')
          expected = {'message'=> 'API HTTP get request to http://127.0.0.1:4599/fake.url failed with status 200 ok'}
          assert_equal expected, result
        end

        def test_private_http_request_unrecognized_http_method
          e = assert_raise AdminGUIHTTPError do
            @admin_gui.send(:http_request, 'fake.url', :unknown, {})
          end
          assert_equal 'Unrecognized HTTP method: unknown', e.message
        end

        def test_root_directory
          assert_match(/\/lib\/armagh\/admin\/application\/www_root$/, @admin_gui.root_directory)
        end

        def test_private_set_auth
          username = 'hacker'
          password = 'secret'
          @admin_gui.send(:set_auth, username, password)
          assert_equal username, @admin_gui.instance_variable_get(:@username)
          assert_equal password, @admin_gui.instance_variable_get(:@password)
        end

        def test_login
          username = 'hacker'
          password = 'secret'
          @admin_gui.expects(:get_json_with_status).once.with('/authenticate.json').returns(:success)
          users = [{"roles"=>[], "username"=>username, "name"=>"Neo", "id"=>"123"}]
          @admin_gui.expects(:get_json).with('/users.json').once.returns(users)
          result = @admin_gui.login(username, password)
          assert_equal [:success, {id: '123', name: 'Neo', roles: []}], result
          assert_equal username, @admin_gui.instance_variable_get(:@username)
          assert_equal password, @admin_gui.instance_variable_get(:@password)
        end

        def test_login_empty_fields
          username = ''
          password = ''
          result = @admin_gui.login(username, password)
          assert_equal [:error, 'Username and/or password cannot be blank.'], result
          assert_nil @admin_gui.instance_variable_get(:@username)
          assert_nil @admin_gui.instance_variable_get(:@password)
        end

        def test_login_failed_authentication
          username = 'hacker'
          password = 'secret'
          @admin_gui.expects(:get_json_with_status).once.with('/authenticate.json').returns([:error, 'failed'])
          result = @admin_gui.login(username, password)
          assert_equal [:error, 'failed'], result
          assert_nil @admin_gui.instance_variable_get(:@username)
          assert_nil @admin_gui.instance_variable_get(:@password)
        end

        def test_login_required_password_reset
          user_id  = '123'
          username = 'hacker'
          password = 'secret'
          @admin_gui.expects(:get_json_with_status).once.with('/authenticate.json').returns(:success)
          users = [{"username"=>username, "id"=>user_id, "required_password_reset"=>true}]
          @admin_gui.expects(:get_json).with('/users.json').once.returns(users)
          result = @admin_gui.login(username, password)
          assert_equal [:change_password, user_id], result
          assert_equal username, @admin_gui.instance_variable_get(:@username)
          assert_equal password, @admin_gui.instance_variable_get(:@password)
        end

        def test_change_password
          user_id = '123'
          username = 'hacker'
          params = {'old'=>'secrey', 'new'=>'crypto', 'con'=>'crypto'}
          @admin_gui.expects(:authenticate?).once.returns(true)
          @admin_gui.expects(:put_json).once.returns([:success, 'user'])
          result = @admin_gui.change_password(user_id, username, params)
          assert_equal [:success, 'user'], result
          assert_equal username,      @admin_gui.instance_variable_get(:@username)
          assert_equal params['new'], @admin_gui.instance_variable_get(:@password)
        end

        def test_change_password_empty_fields
          params = {'old'=>'', 'new'=>'', 'con'=>''}
          expected = [:error, 'One or more required fields are blank.']
          assert_equal expected, @admin_gui.change_password('123', 'hacker', params)
        end

        def test_change_password_mismatch
          params = {'old'=>'secret', 'new'=>'abc', 'con'=>'xyz'}
          expected = [:error, 'New password does not match confirmation.']
          assert_equal expected, @admin_gui.change_password('123', 'hacker', params)
        end

        def test_change_password_old_and_new_equal
          params = {'old'=>'secret', 'new'=>'secret', 'con'=>'secret'}
          expected = [:error, 'New password cannot be the same as current.']
          assert_equal expected, @admin_gui.change_password('123', 'hacker', params)
        end

        def test_change_password_failed_authentication
          params = {'old'=>'fail', 'new'=>'jellybeans', 'con'=>'jellybeans'}
          expected = [:error, 'Incorrect current password provided.']
          @admin_gui.expects(:authenticate?).once.returns(false)
          assert_equal expected, @admin_gui.change_password('123', 'hacker', params)
        end

        def test_logout
          @admin_gui.logout
          assert_nil @admin_gui.instance_variable_get(:@username)
          assert_nil @admin_gui.instance_variable_get(:@password)
        end

        def test_get_status
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'status'=>'ok'}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal 'ok', @admin_gui.get_status
        end

        def test_get_workflows
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflows'=>[]}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal [], @admin_gui.get_workflows
        end

        def test_create_workflow
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflow'=>{'run_mode'=>'stop'}}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:post).once.returns(response)
          assert_equal [:success, {'run_mode'=>'stop'}], @admin_gui.create_workflow('workflow')
        end

        def test_get_workflow
          @admin_gui.expects(:get_workflow_actions).once.returns(['actions_go_here'])
          @admin_gui.expects(:workflow_active?).once.returns(false)
          expected = {
            :actions=>["actions_go_here"],
            :active=>false,
            :created=>nil,
            :updated=>true,
            :workflow=>"workflow"
          }
          assert_equal expected, @admin_gui.get_workflow('workflow', nil, true)
        end

        def test_private_get_workflow_actions
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'actions'=>[]}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal [], @admin_gui.send(:get_workflow_actions, 'workflow')
        end

        def test_private_workflow_active?
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflow'=>{'run_mode'=>'run'}}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_true @admin_gui.send(:workflow_active?, 'workflow')
        end

        def test_private_get_defined_actions
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'defined_actions'=>[]}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal [], @admin_gui.send(:get_defined_actions)
        end

        def test_activate_workflow
          response = {
            'run_mode' => 'run'
          }
          @admin_gui.expects(:patch_json).once.returns([:success, response])
          result = @admin_gui.activate_workflow('dummy')
          assert_equal ['run', response], result
        end

        def test_activate_workflow_failure
          response = 'some error'
          @admin_gui.expects(:patch_json).once.returns([:error, response])
          result = @admin_gui.activate_workflow('dummy')
          expected = ['stop', "Unable to activate workflow dummy: #{response}"]
          assert_equal expected, result
        end

        def test_activate_workflow_unexpected_error
          @admin_gui.expects(:patch_json).once.raises(RuntimeError, 'unexpected error')
          result = @admin_gui.activate_workflow('dummy')
          assert_equal ["stop", "Unable to activate workflow dummy: unexpected error"], result
        end

        def test_deactivate_workflow
          response = {
            'run_mode' => 'stop'
          }
          @admin_gui.expects(:patch_json).once.returns([:success, response])
          result = @admin_gui.deactivate_workflow('dummy')
          assert_equal ['stop', response], result
        end

        def test_deactivate_workflow_failure
          response = 'some error'
          @admin_gui.expects(:patch_json).once.returns([:error, response])
          result = @admin_gui.deactivate_workflow('dummy')
          expected = ['run', "Unable to deactivate workflow dummy: #{response}"]
          assert_equal expected, result
        end

        def test_private_get_defined_parameters
          data = {
            'parameters'=>[
              {'name'=>'name', 'description'=>'description', 'type'=>'type', 'required'=>true, 'prompt'=>'prompt', 'default'=>'default', 'group'=>'group'},
              {'error'=>'some error'},
              {'warning'=>'some warning'}
            ],
            'type'=>'Armagh::SomeType',
            'supertype'=>'Armagh::SomeSuperType'
          }
          @admin_gui.expects(:get_json).once.returns(data)
          result = @admin_gui.send(:get_defined_parameters, 'workflow', 'type')
          expected = {:type=>"Armagh::SomeType",
                      :supertype=>"SomeSuperType",
                      "group"=>[{:default=>"default",
                                 :description=>"description",
                                 :error=>nil,
                                 :name=>"name",
                                 :options=>nil,
                                 :prompt=>"prompt",
                                 :required=>true,
                                 :type=>"type",
                                 :value=>nil,
                                 :warning=>nil}],
                      :errors=>["Validation error: some error"],
                      :warnings=>["Validation warning: some warning"]}
          assert_equal expected, result
        end

        def test_edit_workflow_action
          config = {
            'parameters' => ['config_params'],
            :type        => 'type',
            :supertype   => 'supertype',
          }
          @admin_gui.expects(:get_action_config).once.with('workflow', 'action').returns(config)
          @admin_gui.expects(:workflow_active?).once.returns(false)
          @admin_gui.expects(:get_action_test_callbacks).once.with('type').returns(['test_callbacks'])
          expected = {
            :action=>"action",
            :defined_parameters=>{"parameters"=>["config_params"]},
            :edit_action=>true,
            :locked=>false,
            :supertype=>"supertype",
            :test_callbacks=>["test_callbacks"],
            :type=>"type",
            :workflow=>"workflow"
          }
          assert_equal expected, @admin_gui.edit_workflow_action('workflow', 'action')
        end

        def test_private_get_action_config
          data = {
            'parameters' => [{'name'=>'name', 'description'=>'description', 'type'=>'type', 'required'=>true, 'prompt'=>'prompt', 'default'=>'default', 'group'=>'group'}],
            'type' => 'Armagh::SomeType',
            'supertype' => 'Armagh::SomeSuperType'
          }
          @admin_gui.expects(:get_json).once.returns(data)
          result = @admin_gui.send(:get_action_config, 'workflow', 'action')
          expected = {:type=>"Armagh::SomeType",
                      :supertype=>"SomeSuperType",
                      "group"=>[{:default=>"default",
                                 :description=>"description",
                                 :error=>nil,
                                 :name=>"name",
                                 :options=>nil,
                                 :prompt=>"prompt",
                                 :required=>true,
                                 :type=>"type",
                                 :value=>nil,
                                 :warning=>nil}]}
          assert_equal expected, result
        end

        def test_create_action_config
          parameters = {
            'action' => [{name: 'name', description: 'description', type: 'type', required: true, prompt: 'prompt', default: 'default'}],
            'input' => [{name: 'docspec', defined_states: ['collected']}],
            'output' => [{name: 'docspec', defined_states: ['ready', 'working']}],
            'html' => [{name: 'node', type: 'populated_string'}],
            'rss' => [{name: 'url', type: 'string_array'}],
            'ssl' => [{name: 'keys', type: 'hash'}],
            type: 'Armagh::SomeType',
            supertype: 'SomeSuperType'
          }
          data = {
            'action' => 'action',
            'workflow' => 'workflow',
            'type' => 'Armagh::SomeType',
            'action-name' => 'action_name',
            'input-docspec_type' => 'type',
            'input-docspec_state' => 'state',
            'output-docspec_type' => 'type',
            'output-docspec_state' => 'state',
            'html-node' => '<div*.?<\div>',
            'rss-url' => "www.example.com\x19www.sample.com",
            'ssl-keys' => "cert\x11/var/armagh/cert\x19key\x11/var/armagh/key",
            'splat' => [],
            'captures' => []
          }
          response = [:success]
          @admin_gui.expects(:get_defined_parameters).once.returns(parameters)
          @admin_gui.expects(:post_json).once.returns(response)
          assert_equal :success, @admin_gui.create_action_config(data)
        end

        def test_create_action_config_missing_expected_parameter
          parameters = {
            'action' => [{name: 'name', description: 'description', type: 'type', required: true, prompt: 'prompt', default: 'default'}],
            'input' => [{name: 'docspec'}],
            'output' => [{name: 'docspec'}],
            type: 'Armagh::SomeType',
            supertype: 'SomeSuperType'
          }
          data = {
            'action' => 'action',
            'workflow' => 'workflow',
            'type' => 'Armagh::SomeType',
            'splat' => [],
            'captures' => []
          }
          response = [:error, {'markup' => {}}]
          @admin_gui.expects(:get_defined_parameters).once.returns(parameters)
          @admin_gui.expects(:post_json).once.returns(response)
          @admin_gui.expects(:workflow_active?).once.returns(false)
          @admin_gui.expects(:format_action_config_for_gui).once.returns(parameters)
          @admin_gui.expects(:get_action_test_callbacks).once.returns(nil)
          result = @admin_gui.create_action_config(data)
          expected = [{:action=>"action",
            :defined_parameters=>
             {"action"=>
               [{:default=>"default",
                 :description=>"description",
                 :name=>"name",
                 :prompt=>"prompt",
                 :required=>true,
                 :type=>"type"}],
              "input"=>[{:defined_states=>nil, :name=>"docspec"}],
              "output"=>[{:defined_states=>nil, :name=>"docspec"}]},
            :edit_action=>false,
            :locked=>false,
            :pending_values=>{},
            :supertype=>"SomeSuperType",
            :test_callbacks=>nil,
            :type=>"Armagh::SomeType",
            :workflow=>"workflow"},
            ["Missing expected parameter \"name\" for group \"action\"", {"markup"=>{}}]]
          assert_equal expected, result
        end

        def test_update_action_config
          parameters = {
            'action' => [{name: 'name', description: 'description', type: 'type', required: true, prompt: 'prompt', default: 'default'}],
            type: 'Armagh::SomeType',
            supertype: 'SomeSuperType'
          }
          data = {
            'action' => 'action',
            'workflow' => 'workflow',
            'type' => 'Armagh::SomeType',
            'action-name' => 'action_name',
            'splat' => [],
            'captures' => []
          }
          response = [:success]
          @admin_gui.expects(:get_defined_parameters).once.returns(parameters)
          @admin_gui.expects(:post_json).once.returns(response)
          result = @admin_gui.create_action_config(data)
          assert_equal :success, result
        end

        def test_update_action_config_missing_expected_parameter
          parameters = {
            'action' => [{name: 'name', description: 'description', type: 'type', required: true, prompt: 'prompt', default: 'default'}],
            type: 'Armagh::SomeType',
            supertype: 'SomeSuperType'
          }
          data = {
            'action' => 'action',
            'workflow' => 'workflow',
            'type' => 'Armagh::SomeType',
            'splat' => [],
            'captures' => []
          }
          response = [:error, {}]
          @admin_gui.expects(:get_defined_parameters).once.returns(parameters)
          @admin_gui.expects(:put_json).once.returns(response)
          @admin_gui.expects(:workflow_active?).once.returns(false)
          @admin_gui.expects(:get_action_test_callbacks).once.returns(nil)
          result = @admin_gui.update_action_config(data)
          expected = [{:action=>"action",
                       :defined_parameters=>
                         {"action"=>
                           [{:default=>"default",
                             :description=>"description",
                             :name=>"name",
                             :prompt=>"prompt",
                             :required=>true,
                             :type=>"type"}]},
                       :edit_action=>true,
                       :locked=>false,
                       :pending_values=>{},
                       :supertype=>"SomeSuperType",
                       :test_callbacks=>nil,
                       :type=>"Armagh::SomeType",
                       :workflow=>"workflow"},
                      ["Missing expected parameter \"name\" for group \"action\"", {}]]
          assert_equal expected, result
        end

        def test_import_action_config
          response = [:success]
          @admin_gui.expects(:post_json).once.returns(response)
          config = {
            'type'=>'Armagh::SomeAction',
            'action'=>{
              'name'=>'name',
              'active'=>true
            }
          }
          tempfile = mock('tempfile')
          tempfile.expects(:read).once.returns(config.to_json)
          params = {
            'workflow'=>'workflow',
            'files'=>[
              {tempfile: tempfile, filename: 'filename'}
            ]
          }
          result = @admin_gui.import_action_config(params)
          assert_equal %w(filename).to_json, result
        end

        def test_import_action_config_with_action_class_name
          response = [:success]
          @admin_gui.expects(:post_json).once.returns(response)
          config = {
            'action_class_name'=>'Armagh::SomeAction',
            'action'=>{
              'name'=>'name',
              'active'=>true
            }
          }
          tempfile = mock('tempfile')
          tempfile.expects(:read).once.returns(config.to_json)
          params = {
            'workflow'=>'workflow',
            'files'=>[
              {tempfile: tempfile, filename: 'filename'}
            ]
          }
          result = @admin_gui.import_action_config(params)
          assert_equal %w(filename).to_json, result
        end

        def test_import_action_config_missing_files
          e = assert_raise RuntimeError do
            @admin_gui.import_action_config({})
          end
          assert_equal 'Missing files', e.message
        end

        def test_import_action_config_mismatched_workflow
          config = {
            'action_class_name'=>'Armagh::SomeAction',
            'action'=>{
              'name'=>'name',
              'active'=>true,
              'workflow'=>'another'
            }
          }
          tempfile = mock('tempfile')
          tempfile.expects(:read).once.returns(config.to_json)
          params = {
            'workflow'=>'workflow',
            'files'=>[
              {tempfile: tempfile, filename: 'filename'}
            ]
          }
          e = assert_raise RuntimeError do
            @admin_gui.import_action_config(params)
          end
          assert_equal 'Action belongs to a different workflow: another', e.message
        end

        def test_import_action_config_server_error
          response = [:error, 'some error']
          @admin_gui.expects(:post_json).once.returns(response)
          config = {
            'action_class_name'=>'Armagh::SomeAction',
            'action'=>{
              'name'=>'name',
              'active'=>true
            }
          }
          tempfile = mock('tempfile')
          tempfile.expects(:read).once.returns(config.to_json)
          params = {
            'workflow'=>'workflow',
            'files'=>[
              {tempfile: tempfile, filename: 'filename'}
            ]
          }
          e = assert_raise RuntimeError do
            @admin_gui.import_action_config(params)
          end
          assert_equal 'Unable to import action: some error', e.message
        end

        def test_export_workflow_config
          actions = [{'name'=>'action'}]
          @admin_gui.expects(:get_workflow_actions).once.returns(actions)
          action = {'action'=>[{name:'name', value:'value'}], type:'Armagh::SomeType'}
          @admin_gui.expects(:get_action_config).once.returns(action)
          result = @admin_gui.export_workflow_config('workflow')
          expected = "{\n" +
            "  \"workflow\": \"workflow\",\n" +
            "  \"actions\": [\n" +
            "    {\n" +
            "      \"type\": \"Armagh::SomeType\",\n" +
            "      \"action\": {\n" +
            "        \"name\": \"value\"\n" +
            "      }\n" +
            "    }\n" +
            "  ]\n" +
            "}"
          assert_equal expected, result
        end

        def test_new_workflow_action
          @admin_gui.expects(:get_defined_actions).once.returns(['defined_actions'])
          @admin_gui.expects(:workflow_active?).once.returns(false)
          expected = {
            :active=>false,
            :defined_actions=>["defined_actions"],
            :filter=>"Some::Action::SuperType",
            :previous_action=>"previous_action",
            :workflow=>"workflow"
          }
          assert_equal expected, @admin_gui.new_workflow_action('workflow', 'previous_action', 'Some::Action::SuperType')
        end

        def test_new_action_config
          params = {
            'parameters' => ['params_go_here'],
            :type        => 'type',
            :supertype   => 'supertype'
          }
          @admin_gui.expects(:get_defined_parameters).once.with('workflow', 'action').returns(params)
          @admin_gui.expects(:get_action_test_callbacks).once.with('type').returns(nil)
          expects = {
            :action=>"action",
            :defined_parameters=>{"parameters"=>["params_go_here"]},
            :supertype=>"supertype",
            :test_callbacks=>nil,
            :type=>"type",
            :workflow=>"workflow"
          }
          assert_equal expects, @admin_gui.new_action_config('workflow', 'action')
        end

        def test_private_get_action_test_callbacks
          type = 'Armagh::Some::Type'
          callbacks = [{group: 'group', class: type, method: 'method'}]
          @admin_gui.expects(:get_json).once.returns(callbacks)
          result = @admin_gui.send(:get_action_test_callbacks, type)
          assert_equal callbacks, result
        end

        def test_invoke_action_test_callback
          data = {
            'type'   => 'Armagh::Some::Type',
            'group'  => 'group',
            'method' => 'method'
          }
          response = 'some callback error'
          @admin_gui.expects(:patch_json).once.returns([:success, response])
          result = @admin_gui.invoke_action_test_callback(data)
          assert_equal response, result
        end

        private def mock_log_connection
          BSON.stubs(:ObjectId).returns('mongo_id')
          array = ['la::la::la']
          aggregate = mock('aggregate')
          aggregate.stubs(:to_a).returns(array)
          limit = mock('limit')
          limit.stubs(:aggregate).returns(aggregate)
          limit.stubs(:to_i).returns(10)
          limit.stubs(:to_a).returns(array)
          limit.stubs(:distinct).returns(array)
          skip = mock('skip')
          skip.stubs(:limit).returns(limit)
          sort = mock('sort')
          sort.stubs(:skip).returns(skip)
          projection = mock('projection')
          projection.stubs(:sort).returns(sort)
          find = mock('find')
          find.stubs(:count).returns('1000')
          find.stubs(:skip).returns(skip)
          find.stubs(:projection).returns(projection)
          log = mock('log')
          log.stubs(:find).returns(find)
          Connection.stubs(:log).returns(log)
        end

        def test_logs
          filter = "message\x11blah\x19_id\x11mongo_id\x19timestamp\x111982-01-04\x19pid\x119999\x19level\x11any"
          hide = "pid\x19hostname"
          mock_log_connection
          result = @admin_gui.get_logs(page: 1, limit: 10, sort: {'timestamp'=>-1}, filter: filter, hide: hide)
          expected = {:count=>1000,
            :distinct=>
              {"component"=>["la"],
              "hostname"=>["la::la::la"],
              "level"=>["la::la::la"],
              "pid"=>["la::la::la"],
              "timestamp"=>[nil]},
            :errors=>[],
            :filter=>
              "message\u0011blah\u0019_id\u0011mongo_id\u0019timestamp\u00111982-01-04\u0019pid\u00119999\u0019level\u0011any",
            :hide=>"pid\u0019hostname",
            :limit=>10,
            :logs=>["la::la::la"],
            :page=>1,
            :skip=>0,
            :sort_col=>"timestamp",
            :sort_dir=>-1}
          assert_equal expected, result
        end

        def test_get_logs_empty_filter
          mock_log_connection
          result = @admin_gui.get_logs(page: 1, limit: 10, sort: {'timestamp'=>-1}, filter: '', hide: '')
          expected = {:count=>1000,
            :distinct=>{"component"=>["la"],
              "hostname"=>["la::la::la"],
              "level"=>["la::la::la"],
              "pid"=>["la::la::la"],
              "timestamp"=>[nil]},
            :errors=>[],
            :filter=>"",
            :hide=>"",
            :limit=>10,
            :logs=>["la::la::la"],
            :page=>1,
            :skip=>0,
            :sort_col=>"timestamp",
            :sort_dir=>-1}
          assert_equal expected, result
        end

        def test_get_logs_time_parse_error
          mock_log_connection
          filter = "timestamp\x11fail_me"
          result = @admin_gui.get_logs(page: 1, limit: 10, sort: {'timestamp'=>-1}, filter: filter, hide: nil)
          expected = {:count=>1000,
            :distinct=>
              {"component"=>["la"],
               "hostname"=>["la::la::la"],
               "level"=>["la::la::la"],
               "pid"=>["la::la::la"],
               "timestamp"=>[nil]},
            :errors=>["Unable to filter <strong>timestamp</strong>: no time information in \"fail_me\""],
            :filter=>"timestamp\u0011fail_me",
            :hide=>nil,
            :limit=>10,
            :logs=>["la::la::la"],
            :page=>1,
            :skip=>0,
            :sort_col=>"timestamp",
            :sort_dir=>-1}
          assert_equal expected, result
        end

        def test_get_doc_collections
          collection = mock('collection')
          collection.expects(:namespace).once.returns('armagh.documents.collection')
          Connection.expects(:all_document_collections).once.returns([collection])
          result = @admin_gui.get_doc_collections
          expected = {"armagh.documents.collection"=>"Collection", "armagh.failures"=>"Failures"}
          assert_equal expected, result
        end

        private def mock_doc_connection
          BSON.stubs(:ObjectId).returns('mongo_id')
          count = mock('count')
          count.expects(:count).once.returns(1)
          array = [{doc: true}]
          skip = mock('skip')
          skip.expects(:limit).once.returns(array)
          sort = mock('sort')
          sort.expects(:skip).once.returns(skip)
          doc = mock('doc')
          doc.expects(:sort).once.returns(sort)
          sample = mock('sample')
          sample.expects(:limit).returns([{doc: 'doc'}])
          connection = mock('connection')
          connection.expects(:find).times(3).returns(sample, count, doc)
          all_docs = mock('all_docs')
          all_docs.expects(:find).once.returns(connection)
          Connection.expects(:all_document_collections).once.returns(all_docs)
        end

        def test_get_doc
          params = {
            'collection' => 'collection',
            'page'       => 1,
            'from'       => '1982-01-04',
            'thru'       => '1982-12-27',
            'search'     => 'search'
          }
          mock_doc_connection
          result = @admin_gui.get_doc(params)
          expected = {
            :count=>1,
            :doc=>{:doc=>true},
            :expand=>false,
            :from=>"1982-01-04",
            :page=>0,
            :search=>"search",
            :thru=>"1982-12-27"
          }
          assert_equal expected, result
        end

      end
    end
  end
end
