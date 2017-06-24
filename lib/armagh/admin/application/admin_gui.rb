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

require 'singleton'
require 'httpclient'
require 'cgi'
require 'json'

require 'armagh/actions'

require_relative '../../logging'
require_relative '../../configuration/file_based_configuration'

module Armagh
  module Admin
    module Application

      class AdminGUIError < StandardError; end
      class AdminGUIHTTPError < AdminGUIError; end

      class AdminGUI
        include Singleton

        attr_accessor :ip,
                      :port,
                      :logger

        LOG_LOCATION = '/var/log/armagh/application_admin_gui.log'

        DEFAULTS = {
          'ip' => '127.0.0.1'
        }

        def initialize
          @logger = Logging.set_logger('Armagh::ApplicationAdminGUI')

          begin
            config = Configuration::FileBasedConfiguration.load('Armagh::Admin::Application::API')
          rescue => e
            Logging.ops_error_exception(@logger, e, "Invalid file based configuration for #{self.class.to_s}.  Reverting to default.")
            config = {}
          end

          @config = DEFAULTS.merge(config)
          @config['api_port'] = @config.delete('port')
          @config['port'] = 4600 # TODO move this into the json configuration
          @config.each do |k,v|
            instance_variable_set( "@#{k}", v )
          end
        end

        private def get_json(relative_url, fields = {})
          http_request(relative_url, :get, fields)
        end

        private def get_json_with_status(relative_url, fields = {})
          http_request(relative_url, :get, fields, true)
        end

        private def post_json(relative_url, hash_or_json = {})
          http_request(relative_url, :post, hash_or_json)
        end

        private def put_json(relative_url, hash_or_json = {})
          http_request(relative_url, :put, hash_or_json)
        end

        private def patch_json(relative_url, hash_or_json = {})
          http_request(relative_url, :patch, hash_or_json)
        end

        private def delete_json(relative_url, hash_or_json = {})
          raise NotImplementedError
        end

        private def http_request(relative_url, method, data, get_with_status = false)
          relative_url.sub!(/^\//, '')
          relative_url.gsub!(/\ /, '%20')
          url    = "http://#{@ip}:#{@api_port}/#{relative_url}"
          header = {'ContentType' => 'application/json'}
          body   = data.is_a?(JSON) ? data : data.to_json

          client = HTTPClient.new
          client.set_auth(url, @username, @password)

          response =
            case method
            when :get
              client.get(url,    body)
            when :post
              client.post(url,   body: body, header: header)
            when :put
              client.put(url,    body: body, header: header)
            when :patch
              client.patch(url,  body: body, header: header)
            when :delete
              client.delete(url, body)
            else
              raise AdminGUIHTTPError, "Unrecognized HTTP method: #{method}"
            end

          begin
            json = JSON.parse(response.body)
          rescue JSON::ParserError
            json = {'server_error_detail' => {'message' =>
              "API HTTP #{method} request to #{url} failed with status #{response.status} #{response.reason}"}}
          end
          status = response.status == 200 ? :ok : :error

          if json.is_a?(Hash)
            json = json['client_error_detail'] if json.has_key?('client_error_detail')
            json = json['server_error_detail'] if json.has_key?('server_error_detail')
          end

          case method
          when :get
            if get_with_status
              [status, json]
            else
              if status == :ok
                json
              else
                raise AdminGUIHTTPError, json['message']
              end
            end
          when :post, :put, :patch
            [status, json]
          end
        end

        def set_auth(username, password)
          @username = username
          @password = password
        end

        def root_directory
          File.join( __dir__, 'www_root' )
        end

        def shutdown(restart: false)
          `armaghd #{restart ? 'restart' : 'stop'}`
        end

        def get_status
          get_json('/status.json')
        end

        def get_workflows
          get_json('/workflows.json')
        end

        def create_workflow(workflow)
          post_json("/workflow/#{workflow}/new.json")
        end

        def get_workflow(workflow, created, updated)
          {
            workflow: workflow,
            actions:  get_workflow_actions(workflow),
            active:   workflow_active?(workflow),
            created:  created,
            updated:  updated
          }
        end

        private def get_workflow_actions(workflow)
          get_json("/workflow/#{workflow}/actions.json")
        end

        private def workflow_active?(workflow)
          status = get_json("/workflow/#{workflow}/status.json")
          status['run_mode'] != 'stop'
        end

        def activate_workflow(workflow)
          change_workflow_status(workflow, :activate)
        end

        def deactivate_workflow(workflow)
          change_workflow_status(workflow, :deactivate)
        end

        private def change_workflow_status(workflow, status_change)
          unchanged_status = status_change == :activate ? 'stop' : 'run'
          status, response =
            patch_json("/workflow/#{workflow}/#{status_change == :activate ? 'run' : 'stop'}.json")
        rescue => e
          [unchanged_status, "Unable to #{status_change} workflow #{workflow}: #{e.message}"]
        else
          if status == :ok
            [response['run_mode'], response]
          else
            [unchanged_status, "Unable to #{status_change} workflow #{workflow}: #{response['message']}"]
          end
        end

        private def get_defined_actions
          get_json('/actions/defined.json')
        end

        def import_action_config(params)
          workflow = params['workflow']
          raise 'Missing files' unless params.has_key?('files')
          imported = []
          params['files'].each do |file|
            config = file[:tempfile].read
            config = JSON.parse(config)
            wf     = config.dig('action', 'workflow')
            raise "Action belongs to a different workflow: #{wf}" if wf && wf != workflow
            config['type'] = config.delete('action_class_name') if config['action_class_name']
            config['action']['active']   = false
            config['action']['workflow'] = workflow

            status, response = post_json("/workflow/#{workflow}/action/config.json", config)

            raise "Unable to import action: #{response['message']}" unless status == :ok
            imported << file[:filename]
          end
          imported.to_json
        end

        def export_workflow_config(workflow)
          export  = {
            'workflow' => workflow,
            'actions'  => []
          }
          actions = get_workflow_actions(workflow)
          actions.each do |action|
            config = get_action_config(workflow, action['name'])
            _export = {'type' => config[:type]}
            config.each do |group, params|
              next unless params.is_a?(Array)
              _export[group] ||= {}
              params.each do |param|
                next if param[:value].nil?
                _export[group][param[:name]] = param[:name] == 'active' ? true : param[:value]
              end
            end
            export['actions'] << _export
          end
          JSON.pretty_generate(export)
        end

        def new_workflow_action(workflow, previous_action, filter)
          {
            workflow:        workflow,
            active:          workflow_active?(workflow),
            defined_actions: get_defined_actions,
            previous_action: previous_action,
            filter:          filter
          }
        end

        def new_action_config(workflow, action)
          params = get_defined_parameters(workflow, action)
          {
            workflow:           workflow,
            action:             action,
            type:               params.delete(:type),
            supertype:          params.delete(:supertype),
            defined_parameters: params
          }
        end

        private def format_action_config_for_gui(config)
          formatted_config = {
            type:      config['type'],
            supertype: config['supertype'].split('::').last
          }

          config['parameters'].each do |param|
            unless param['name']
              group = param['group'] ? " in #{param['group']}: " : ': '
              if param['error']
                formatted_config[:errors] ||= []
                formatted_config[:errors] << "Validation error#{group}#{param['error']}"
              end
              if param['warning']
                formatted_config[:warnings] ||= []
                formatted_config[:warnings] << "Validation warning#{group}#{param['warning']}"
              end
              next
            end

            group = param['group']
            formatted_config[group] ||= []
            formatted_param = {
              name:        param['name'],
              description: param['description'],
              type:        param['type'],
              options:     param['options'],
              required:    param['required'],
              prompt:      param['prompt'],
              default:     param['default'],
              value:       param['value'],
              warning:     param['warning'],
              error:       param['error']
            }

            valid_states = Array(param['valid_state'] || param['valid_states'])
            formatted_param[:defined_states] = valid_states if valid_states.any?

            formatted_config[group] << formatted_param
          end

          formatted_config.sort_by { |k, _| k == 'action' ? 0 : 1 }.to_h
        end

        private def get_defined_parameters(workflow, type)
          fields = {'type' => type}
          config = get_json("/workflow/#{workflow}/action/config.json", fields)
          format_action_config_for_gui(config)
        end

        private def get_action_config(workflow, action)
          config = get_json("/workflow/#{workflow}/action/#{action}/description.json")
          format_action_config_for_gui(config)
        end

        def edit_workflow_action(workflow, action)
          config = get_action_config(workflow, action)
          type   = config.delete(:type)
          {
            locked:             workflow_active?(workflow),
            workflow:           workflow,
            action:             action,
            type:               type,
            supertype:          config.delete(:supertype),
            edit_action:        true,
            defined_parameters: config,
            test_callbacks:     get_action_test_callbacks(type)
          }
        end

        def create_action_config(data)
          save_action_config(data, new_action: true)
        end

        def update_action_config(data)
          save_action_config(data, new_action: false)
        end

        private def save_action_config(data, new_action:)
          data.delete('splat')
          data.delete('captures')

          workflow           = data.delete('workflow')
          action             = data.delete('action')
          type               = data.delete('type')
          docspec_groups     = %w(input output)
          defined_parameters = get_defined_parameters(workflow, type)
                               defined_parameters.delete(:type)
          supertype          = defined_parameters.delete(:supertype)
          defined_states     = {}
          errors             = []
          new_config         = {'type' => type}

          docspec_groups.each do |docspec|
            data.keys.grep(/^#{docspec}-.*?_type$/).each do |field|
              doctype  = data[field]
              docstate = data[field.sub(/_type$/, '_state')]
              name  = field.sub(/^#{docspec}-/, '').sub(/_(?:type|state)/, '')
              new_config[docspec] ||= {}
              new_config[docspec][name] = "#{doctype}:#{docstate}"
            end
          end

          defined_parameters.each do |group, params|
            if docspec_groups.include?(group)
              params.each do |param|
                defined_states[group] ||= {}
                defined_states[group][param[:name]] = param[:defined_states]
              end
              next
            end

            params.each do |param|
              key = "#{group}-#{param[:name]}"

              unless data.include?(key)
                errors << "Missing expected parameter #{param[:name].inspect} for group #{group.inspect}"
                next
              end

              value = data[key]
              case param[:type]
              when 'populated_string'
                next if value.to_s.strip.empty?
              when 'string_array'
                value = value.split("\x19")
                value = param[:default] if value.empty?
              when 'hash'
                new_hash = {}
                value.split("\x19").each do |pair|
                  k, v = pair.split("\x11")
                  new_hash[k] = v
                end
                value = new_hash
                value = param[:default] if value.empty?
              end
              param[:value] = value

              new_config[group] ||= {}
              new_config[group][param[:name]] = value
            end
          end

          status, response =
            if new_action
              post_json("/workflow/#{workflow}/action/config.json", new_config)
            else
              put_json("/workflow/#{workflow}/action/#{action}/config.json", new_config)
            end

          if status == :ok && errors.empty?
            :success
          else
            errors << response['message'] if response['message']
            if response.has_key?('markup')
              config = format_action_config_for_gui(response['markup'])
              config.delete(:type)
              config.delete(:supertype)

              docspec_groups&.each do |group|
                config[group]&.each do |p|
                  if defined_states[group].has_key?(p[:name])
                    p[:defined_states] = defined_states[group][p[:name]]
                  end
                end
              end

              errors += config.delete(:errors) if config[:errors]
              errors += config.delete(:warnings) if config[:warnings]
            else
              config = defined_parameters
            end

            data = {
              locked:             workflow_active?(workflow),
              workflow:           workflow,
              action:             action,
              type:               type,
              supertype:          supertype,
              edit_action:        !new_action,
              defined_parameters: config,
              pending_values:     data,
              test_callbacks:     get_action_test_callbacks(type)
            }
            [data, errors]
          end
        end

        private def get_action_test_callbacks(type)
          get_json("/test/#{type}/callbacks.json")
        end

        def invoke_action_test_callback(data)
          status, response = patch_json("/test/invoke_callback.json", data)
          raise "Unable to invoke action test callback method #{data['method']} for action type #{data['type']}" unless status == :ok
          response
        end

        def get_logs(page:, limit:, sort:, filter:, hide:)
          errors = []
          page   = page.to_i
          page   = 1 if page <= 0
          limit  = limit.to_i
          limit  = 20 if limit <= 0
          skip   = page * limit - limit
          sort   = {sort.keys.first ? sort.keys.first : 'timestamp'=>
                   sort.values.first ? sort.values.first.to_i : -1}

          query =
            if filter.to_s.strip.empty? || filter == '{}'
              {}
            else
              _filter = {}
              filter.split("\x19").each do |column|
                column, value = column.split("\x11")
                next unless value
                value.strip!

                if column == 'message'
                  _filter[:$or] = [
                    {'message' => /#{value}/i},
                    {'exception.class' => /#{value}/i},
                    {'exception.message' => /#{value}/i},
                    {'exception.cause.class' => /#{value}/i},
                    {'exception.cause.message' => /#{value}/i}
                  ]
                  next
                end

                _filter[column] =
                  case column
                  when '_id'
                    BSON::ObjectId(value)
                  when 'timestamp'
                    begin
                      time = Time.parse(value).utc
                    rescue => e
                      errors << "Unable to filter <strong>#{column}</strong>: #{e.message}"
                      {}
                    else
                      {
                        :$gte => Time.new(time.year, time.month, time.day, 00, 00, 00, '+00:00'),
                        :$lte => Time.new(time.year, time.month, time.day, 23, 59, 59, '+00:00')
                      }
                    end
                  when 'pid'
                    value.to_i
                  else
                   /#{value}/i
                  end
              end
              _filter
            end

          projection =
            if hide.to_s.strip.empty? || hide == '{}'
              {}
            else
              _hide = {}
              hide.split("\x19").each do |column|
                next if column.empty?
                _hide[column] = 0
              end
              _hide
            end

          count = Connection.log.find(query).count.to_i

          {
            count:    count,
            page:     skip > count ? 1 : page,
            limit:    limit,
            skip:     skip,
            sort_col: sort.keys.first,
            sort_dir: sort.values.first,
            filter:   filter,
            hide:     hide,
            distinct: {
              'timestamp' => Connection.log
                .find(query)
                .skip(skip)
                .limit(limit)
                .aggregate([
                  {'$project' => {'date' => {'$substr'=>['$timestamp', 0, 10]}}},
                  {'$group'   => {'_id'  => '$date'}}
                ])
                .to_a.map { |date| date['_id'] }
                .sort,
              'component' => Connection.log
                .find(query)
                .skip(skip)
                .limit(limit)
                .distinct('component').to_a
                .map { |component|
                  split = component.split('::')
                  split.size == 4 ? split[2] : split.last
                }
                .uniq
                .sort,
              'level' => Connection.log
                .find(query)
                .skip(skip)
                .limit(limit)
                .distinct('level')
                .to_a
                .sort,
              'hostname' => Connection.log
                .find(query)
                .skip(skip)
                .limit(limit)
                .distinct('hostname')
                .to_a
                .sort,
              'pid' => Connection.log
                .find(query)
                .skip(skip)
                .limit(limit)
                .distinct('pid')
                .to_a
                .sort
            },
            logs: Connection.log
                    .find(query)
                    .projection(projection)
                    .sort(sort)
                    .skip(skip)
                    .limit(limit)
                    .to_a,
            errors: errors
          }
        end

      end
    end
  end
end
