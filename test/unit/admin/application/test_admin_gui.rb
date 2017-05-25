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
require_relative '../../../../lib/admin/application/admin_gui'

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
          expected = {'message'=>'stuff'}
          assert_equal expected, result
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
          data = {'message'=>'stuff'}
          assert_equal [:ok, data], result
        end

        def test_private_post_json
          data = {'field'=>'value'}
          response = mock('response')
          response.stubs(:status).returns(200)
          response.stubs(:body).returns(data.to_json)
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'ok.url')
          expected = [:ok, data]
          assert_equal expected, result
        end

        def test_private_post_json_error
          response = mock('response')
          response.stubs(:status).returns(400)
          data = {'message'=>'some error'}
          response.stubs(:body).returns({'client_error_detail'=>data}.to_json)
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'error.url')
          expected = [:error, data]
          assert_equal expected, result
        end

        def test_private_post_json_http_404
          response = mock('response')
          response.stubs(:status).returns(404)
          response.stubs(:reason).returns('not found')
          response.stubs(:body).returns('body')
          HTTPClient.any_instance.expects(:post).once.returns(response)
          result = @admin_gui.send(:post_json, 'missing.url')
          expected = {'message' => 'API HTTP post request to http://127.0.0.1:4599/missing.url failed with status 404 not found'}
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
          expected = {'message'=>
            'API HTTP get request to http://127.0.0.1:4599/fake.url failed with status 200 ok'}
          assert_equal expected, result
        end

        def test_set_auth
          @admin_gui.set_auth('hacker', 'secret')
          assert_equal 'hacker', @admin_gui.instance_variable_get(:@username)
          assert_equal 'secret', @admin_gui.instance_variable_get(:@password)
        end

        def test_root_directory
          assert_match(/\/lib\/admin\/application\/www_root$/, @admin_gui.root_directory)
        end

        def test_get_status
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'status'=>'ok'}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal expected, @admin_gui.get_status
        end

        def test_get_workflows
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflows'=>[]}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal expected, @admin_gui.get_workflows
        end

        def test_new_workflow
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflow'=>{'run_mode'=>'stop'}}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal [:ok, expected], @admin_gui.new_workflow('workflow')
        end

        def test_get_workflow_actions
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflow'=>{'actions'=>[]}}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal expected, @admin_gui.get_workflow_actions('workflow')
        end

        def test_workflow_active?
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'workflow'=>{'run_mode'=>'run'}}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_true @admin_gui.workflow_active?('workflow')
        end

        def test_get_defined_actions
          response = mock('response')
          response.stubs(:status).returns(200)
          expected = {'defined_actions'=>[]}
          response.stubs(:body).returns(expected.to_json)
          HTTPClient.any_instance.expects(:get).once.returns(response)
          assert_equal expected, @admin_gui.get_defined_actions
        end

        def test_activate_workflow
          response = {
            'run_mode' => 'run'
          }
          @admin_gui.expects(:get_json_with_status).once.returns([:ok, response])
          result = @admin_gui.activate_workflow('dummy')
          expected = ['run', response]
          assert_equal expected, result
        end

        def test_activate_workflow_failure
          response = {
            'message' => 'some error'
          }
          @admin_gui.expects(:get_json_with_status).once.returns([:error, response])
          result = @admin_gui.activate_workflow('dummy')
          expected = ['stop', "Unable to activate workflow dummy: #{response['message']}"]
          assert_equal expected, result
        end

        def test_activate_workflow_unexpected_error
          @admin_gui.expects(:get_json_with_status).once.raises(RuntimeError, 'unexpected error')
          result = @admin_gui.activate_workflow('dummy')
          assert_equal ["stop", "Unable to activate workflow dummy: unexpected error"], result
        end

        def test_deactivate_workflow
          response = {
            'run_mode' => 'stop'
          }
          @admin_gui.expects(:get_json_with_status).once.returns([:ok, response])
          result = @admin_gui.deactivate_workflow('dummy')
          expected = ['stop', response]
          assert_equal expected, result
        end

        def test_deactivate_workflow_failure
          response = {
            'message' => 'some error'
          }
          @admin_gui.expects(:get_json_with_status).once.returns([:error, response])
          result = @admin_gui.deactivate_workflow('dummy')
          expected = ['run', "Unable to deactivate workflow dummy: #{response['message']}"]
          assert_equal expected, result
        end

        def test_get_defined_parameters
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
          result = @admin_gui.get_defined_parameters('workflow', 'type')
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

        def test_get_action_config
          data = {
            'parameters' => [{'name'=>'name', 'description'=>'description', 'type'=>'type', 'required'=>true, 'prompt'=>'prompt', 'default'=>'default', 'group'=>'group'}],
            'type' => 'Armagh::SomeType',
            'supertype' => 'Armagh::SomeSuperType'
          }
          @admin_gui.expects(:get_json).once.returns(data)
          result = @admin_gui.get_action_config('workflow', 'action')
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
          response = [:ok]
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
            ["Missing expected parameter \"name\" for group \"action\""]]
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
          response = [:ok]
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
          @admin_gui.expects(:post_json).once.returns(response)
          @admin_gui.expects(:workflow_active?).once.returns(false)
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
                      ["Missing expected parameter \"name\" for group \"action\""]]
          assert_equal expected, result
        end

        def test_import_action_config
          response = [:ok]
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
          expected = %w(filename).to_json
          assert_equal expected, result
        end

        def test_import_action_config_with_action_class_name
          response = [:ok]
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
          expected = %w(filename).to_json
          assert_equal expected, result
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
          response = [:error, {'message'=>'some error'}]
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
          expected = "{\"workflow\":\"workflow\",\"actions\":[{\"type\":\"Armagh::SomeType\",\"action\":{\"name\":\"value\"}}]}"
          assert_equal expected, result
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

      end
    end
  end
end
