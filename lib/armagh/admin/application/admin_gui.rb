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
require 'uri'
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

        def root_directory
          File.join( __dir__, 'www_root' )
        end

        private def get_json(user, relative_url, query = {})
          http_request(user, relative_url, :get, query)
        end

        private def get_json_with_status(user, relative_url, query = {})
          http_request(user, relative_url, :get, query, true)
        end

        private def post_json(user, relative_url, hash_or_json = {})
          http_request(user, relative_url, :post, hash_or_json)
        end

        private def put_json(user, relative_url, hash_or_json = {})
          http_request(user, relative_url, :put, hash_or_json)
        end

        private def patch_json(user, relative_url, hash_or_json = {})
          http_request(user, relative_url, :patch, hash_or_json)
        end

        private def delete_json(user, relative_url, query = {})
          http_request(user, relative_url, :delete, query)
        end

        private def http_request(user, relative_url, method, data, get_with_status = false)
          relative_url.sub!(/^\//, '')
          url    = URI.encode("http://#{@ip}:#{@api_port}/#{relative_url}")
          header = {'ContentType' => 'application/json'}
          query  = data
          json   = data.is_a?(JSON) ? data : data.to_json

          client = HTTPClient.new
          client.set_auth(url, user.username, user.password)

          response =
            case method
            when :get
              client.get(url, query)
            when :post
              client.post(url, json, header: header)
            when :put
              client.put(url, json, header: header)
            when :patch
              client.patch(url, json, header: header)
            when :delete
              client.delete(url, query)
            else
              raise AdminGUIHTTPError, "Unrecognized HTTP method: #{method}"
            end

          begin
            json = JSON.parse(response.body)
          rescue JSON::ParserError
            json = {'server_error_detail'=>{'message'=>
              "API HTTP #{method} request to #{url} failed with status #{response.status} #{response.reason}"}}
          end

          status = response.status == 200 ? :success : :error
          json   = json[json.keys.first] if json.is_a?(Hash) && json.keys.size == 1
          json   = json['message'] if status == :error && json.respond_to?(:has_key?) && json&.has_key?('message')

          case method
          when :get
            if get_with_status
              [status, json]
            else
              raise AdminGUIHTTPError, json if status == :error
              json
            end
          when :post, :put, :patch, :delete
            [status, json]
          end
        end

        private def authenticate(username, password)
          user = Struct.new(:username, :password).new(username, password)
          get_json_with_status(user, '/authenticate.json')
        end

        private def authenticated?(username, password)
          authenticate(username, password).first == :success
        end

        def login(username, password)
          if username.strip.empty? || password.strip.empty?
            [:error, 'Username and/or password cannot be blank.']
          else
            authenticate(username, password)
          end
        end

        def change_password(params)
          username = params['username']
          old      = params['old'].strip
          new      = params['new'].strip
          con      = params['con'].strip

          if old.empty? || new.empty? || con.empty?
            [:error, 'One or more required fields are blank.']
          elsif new != con
            [:error, 'New password does not match confirmation.']
          elsif !authenticated?(username, old)
            [:error, 'Incorrect current password provided.']
          else
            user = Struct.new(:username, :password).new(username, old)
            fields = {'password' => new}
            post_json(user, '/update_password.json', fields)
          end
        end

        def shutdown(user, restart: false)
          raise 'Insufficient user permissions to perform this action.' unless user.roles.include? 'application_admin'
          `armaghd #{restart ? 'restart' : 'stop'}`
        end

        def get_status(user)
          get_json(user, '/status.json')
        end

        def get_workflow_alerts(user,workflow)
          get_json(user, '/workflow/#{workflow}/alerts.json')
        end

        def get_workflows(user)
          get_json(user, '/workflows.json')
        end

        def create_workflow(user, workflow)
          post_json(user, "/workflow/#{workflow}/new.json")
        end

        def get_workflow(user, workflow, created, updated)
          {
            workflow: workflow,
            actions:  get_workflow_actions(user, workflow),
            active:   workflow_active?(user, workflow),
            created:  created,
            updated:  updated
          }
        end

        private def get_workflow_actions(user, workflow)
          get_json(user, "/workflow/#{workflow}/actions.json")
        end

        private def workflow_active?(user, workflow)
          status = get_json(user, "/workflow/#{workflow}/status.json")
          status['run_mode'] != 'stopped'
        end

        def activate_workflow(user, workflow)
          change_workflow_status(user, workflow, :activate)
        end

        def deactivate_workflow(user, workflow)
          change_workflow_status(user, workflow, :deactivate)
        end

        private def change_workflow_status(user, workflow, status_change)
          unchanged_status = status_change == :activate ? 'stop' : 'run'
          status, response =
            patch_json(user, "/workflow/#{workflow}/#{status_change == :activate ? 'run' : 'stop'}.json")
        rescue => e
          [unchanged_status, "Unable to #{status_change} workflow #{workflow}: #{e.message}"]
        else
          if status == :success
            [response['run_mode'], response]
          else
            [unchanged_status, "Unable to #{status_change} workflow #{workflow}: #{response}"]
          end
        end

        private def get_defined_actions(user)
          get_json(user, '/actions/defined.json')
        end

        def import_workflow(user, params)
          errors   = []
          imported = []
          files    = params['files']
          raise 'No JSON file(s) found to import.' unless files&.any?

          files.each do |file|
            begin
              data = JSON.parse(file[:tempfile].read)
            rescue => e
              errors << "Unable to parse workflow JSON file #{file[:filename].inspect}: #{e}"
              next
            end

            status, response = post_json(user, '/workflow/import.json', data)

            if status == :success
              imported << response
            else
              response.sub!(/^(Unable to import )workflow\./, "\\1workflow file #{file[:filename].inspect}.")
              errors << response
            end
          end

          {'imported'=>imported, 'errors'=>errors}.to_json
        end

        def export_workflow(user, workflow)
          get_json(user, "/workflow/#{workflow}/export.json")
        end

        def new_workflow_action(user, workflow, previous_action, filter)
          {
            workflow:        workflow,
            active:          workflow_active?(user, workflow),
            defined_actions: get_defined_actions(user),
            previous_action: previous_action,
            filter:          filter
          }
        end

        def new_action_config(user, workflow, action)
          params    = get_defined_parameters(user, workflow, action)
          type      = params.delete(:type)
          supertype = params.delete(:supertype)
          {
            workflow:           workflow,
            action:             action,
            type:               type,
            supertype:          supertype,
            defined_parameters: params,
            test_callbacks:     get_action_test_callbacks(user, type)
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

        private def get_defined_parameters(user, workflow, type)
          fields = {'type' => type}
          config = get_json(user, "/workflow/#{workflow}/action/config.json", fields)
          format_action_config_for_gui(config)
        end

        private def get_action_config(user, workflow, action)
          config = get_json(user, "/workflow/#{workflow}/action/#{action}/description.json")
          format_action_config_for_gui(config)
        end

        def edit_workflow_action(user, workflow, action)
          config = get_action_config(user, workflow, action)
          type   = config.delete(:type)
          {
            locked:             workflow_active?(user, workflow),
            workflow:           workflow,
            action:             action,
            type:               type,
            supertype:          config.delete(:supertype),
            edit_action:        true,
            defined_parameters: config,
            test_callbacks:     get_action_test_callbacks(user, type)
          }
        end

        def create_action_config(user, data)
          save_action_config(user, data, new_action: true)
        end

        def update_action_config(user, data)
          save_action_config(user, data, new_action: false)
        end

        private def save_action_config(user, data, new_action:)
          data.delete('splat')
          data.delete('captures')

          workflow           = data.delete('workflow')
          action             = data.delete('action')
          type               = data.delete('type')
          docspec_groups     = %w(input output)
          defined_parameters = get_defined_parameters(user, workflow, type)
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
              when 'string'
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
              post_json(user, "/workflow/#{workflow}/action/config.json", new_config)
            else
              put_json(user, "/workflow/#{workflow}/action/#{action}/config.json", new_config)
            end

          if status == :success && errors.empty?
            status
          else
            errors << response
            if response.respond_to?(:has_key?) && response.has_key?('markup')
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
              locked:             workflow_active?(user, workflow),
              workflow:           workflow,
              action:             action,
              type:               type,
              supertype:          supertype,
              edit_action:        !new_action,
              defined_parameters: config,
              pending_values:     data,
              test_callbacks:     get_action_test_callbacks(user, type)
            }
            [data, errors]
          end
        end

        private def get_action_test_callbacks(user, type)
          get_json(user, "/test/#{type}/callbacks.json")
        end

        def invoke_action_test_callback(user, data)
          _status, response = patch_json(user, "/test/invoke_callback.json", data)
          [response ? :error : :success, response].to_json
        end

        def get_logs(user, page:, limit:, sort:, filter:, hide:)
          # TODO move this to the API and create a modal
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

        def get_doc_collections(user) # TODO move this to the API
          collections = {'armagh.failures' => 'Failures'}
          Connection.all_document_collections.each do |collection|
            id    = collection.namespace
            label = id[/armagh\.documents\.?(\w+)$/, 1]
            collections[id] = label&.gsub(/(?:^|_)\w/) { |x| x.sub(/_/, ' ').upcase } || 'Pending Publish'
          end
          collections
        end

        def get_doc(user, params) # TODO move this to the API and create a modal
          query  = {}
          ts     = 'updated_timestamp'
          id     = params['collection']
          page   = params['page'].to_i - 1
          page   = 0 if page < 0
          from   = params['from']
          thru   = params['thru']
          search = params['search']

          collection =
            case id
            when 'armagh.failures'
              Connection.failures
            else
              ts = 'document_timestamp'
              Connection.all_document_collections.find { |c| c.namespace == id }
            end
          raise AdminGUIError, "Unexpected document collection #{id.inspect}" unless collection

          unless from.empty?
            from = Time.parse(from)
            query[ts] = {:$gte => Time.new(from.year, from.month, from.day, 00, 00, 00, '+00:00')}
          end

          unless thru.empty?
            thru = Time.parse(thru)
            query[ts] ||= {}
            query[ts].merge!({:$lte => Time.new(thru.year, thru.month, thru.day, 23, 59, 59, '+00:00')})
          end

          unless search.empty?
            sample = collection.find().limit(1).to_a.first
            fields = get_doc_searchable_fields(sample)
            query['$or'] =
              fields.map! do |field|
                {field => /#{search}/i}
              end
            query['$or'] << {'_id' => BSON::ObjectId(search)} if BSON::ObjectId.legal?(search)
          end

          {
            page:   page,
            from:   params['from'],
            thru:   params['thru'],
            search: params['search'],
            count:  collection.find(query).count,
            doc:    collection.find(query).sort(ts => -1).skip(page).limit(1).to_a.first,
            expand: params['expand'] == 'true'
          }
        end

        private def get_doc_searchable_fields(doc, ancestry = nil)
          fields = []
          doc&.each do |key, value|
            case value
            when String
              fields << "#{ancestry + '.' if ancestry}#{key}"
            when BSON::Document
              fields << get_doc_searchable_fields(value, "#{ancestry + '.' if ancestry}#{key}")
            end
          end
          fields.flatten
        end

      end
    end
  end
end
