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

require 'facets/kernel/constant'

require_relative '../../logging'
require_relative '../../configuration/file_based_configuration'
require_relative '../../launcher/launcher'
require_relative '../../actions/workflow_set'
require_relative '../../document/document'
require_relative '../../actions/gem_manager'
require_relative '../../utils/scheduled_action_trigger'
require_relative '../../authentication'
require_relative '../../status'
require_relative '../../connection'
require_relative '../../utils/action_helper'
require_relative '../../agent/agent'
require_relative '../../authentication/configuration'
require_relative '../../utils/archiver'
require_relative '../../utils/password'
require_relative '../../logging/alert'

module Armagh
  module Admin
    module Application

      class APIClientError < StandardError
        attr_reader :markup
        def initialize( message, markup: nil )
          @markup = markup
          super( message )
        end
      end

      class APIAuthenticationError < StandardError; end

      class API
        include Singleton

        attr_accessor :ip,
                      :port,
                      :key_filepath,
                      :cert_filepath,
                      :verify_peer,
                      :cluster_design_filepath,
                      :logger

        DEFAULTS = {
            'ip'             => '127.0.0.1',
            'port'           => 4599,
            'key_filepath'   => '/home/armagh/.ssl/privkey.pem',
            'cert_filepath'  => '/home/armagh/.ssl/cert.pem'
        }

        def initialize
          @logger = Logging.set_logger('Armagh::ApplicationAdminAPI')

          Connection.require_connection(@logger)

          begin
            config  = Configuration::FileBasedConfiguration.load( self.class.to_s )
          rescue => e
            Logging.ops_error_exception(@logger, e, "Invalid file based configuration for #{self.class.to_s}.  Reverting to default.")
            config = {}
          end

          @config = DEFAULTS.merge config
          @config.delete 'key_filepath' unless File.exists? @config[ 'key_filepath' ]
          @config.delete 'cert_filepath' unless File.exists? @config[ 'cert_filepath' ]

          @config.each do |k,v|
            instance_variable_set( "@#{k}", v )
          end

          @gem_versions = Actions::GemManager.instance.activate_installed_gems(@logger)
        end

        def using_ssl?
          ( @config['key_filepath'] and (!@config['key_filepath'].empty?) and @config['cert_filepath'] and (!@config['cert_filepath'].empty?) )
        end

        def check_params(params, required_params)
          Array(required_params).each do |required|
            raise APIClientError, "A parameter named '#{required}' is missing but is required." if params[required].nil?
          end

          true
        end

        def root_directory
          File.join( __dir__, 'www_root' )
        end

        def get_agent_status
          Armagh::Status::AgentStatus.find_all(raw: true)
        end

        def get_launcher_status
          Armagh::Status::LauncherStatus.find_all(raw: true)
        end

        def get_status
          agents = get_agent_status
          launchers = get_launcher_status

          launchers.each do |launcher|
            launcher['agents'] = agents.find_all {|agent| agent['hostname'] == launcher['hostname']}
          end

          alert_counts = Armagh::Logging::Alert.get_counts

          { 'launchers' => launchers,
            'alert_counts' => alert_counts }
        end

        def get_all_launcher_configurations
          configs = {}

          Launcher.find_all_configurations(Connection.config).each do |_klass, config|
            configs[config.__name] = config.serialize['values']
          end

          configs
        end

        def create_or_update_launcher_configuration(name, values)
          begin
            current_config = Launcher.find_configuration(Connection.config, name)
            if current_config
              config = current_config.update_replace( values )
            else
              config = Launcher.create_configuration( Connection.config, name, values, maintain_history: true )
            end
          rescue Configh::ConfigInitError, Configh::ConfigValidationError
            raise APIClientError.new( 'Invalid launcher config', markup: Launcher.edit_configuration( values))
          end
          config.serialize['values']
        end

        def get_launcher_configuration(name)
          config = Launcher.find_configuration(Connection.config, name)
          config.nil? ? nil : config.serialize['values']
        end

        def create_or_update_agent_configuration(values)
          begin
            current_config = Agent.find_configuration(Connection.config, Agent::CONFIG_NAME)
            if current_config
              config = current_config.update_replace(values)
            else
              config = Agent.create_configuration(Connection.config, Agent::CONFIG_NAME, values, maintain_history: true)
            end
          rescue Configh::ConfigInitError, Configh::ConfigValidationError
            raise APIClientError.new('Invalid agent config', markup: Agent.edit_configuration(values))
          end

          config.serialize['values']
        end

        def get_agent_configuration
          config = Agent.find_configuration(Connection.config, Agent::CONFIG_NAME)
          config.nil? ? nil : config.serialize['values']
        end

        def create_or_update_authentication_configuration(values)
          begin
            current_config = Authentication::Configuration.find_configuration(Connection.config, Authentication::Configuration::CONFIG_NAME)
            if current_config
              config = current_config.update_replace(values)
            else
              config = Authentication::Configuration.create_configuration(Connection.config, Authentication::Configuration::CONFIG_NAME, values, maintain_history: true)
            end
          rescue Configh::ConfigInitError, Configh::ConfigValidationError
            raise APIClientError.new('Invalid authentication config', markup: Authentication::Configuration.edit_configuration(values))
          end

          config.serialize['values']
        end

        def get_authentication_configuration
          config = Authentication::Configuration.find_configuration(Connection.config, Authentication::Configuration::CONFIG_NAME)
          config.nil? ? nil : config.serialize['values']
        end

        def create_or_update_archive_configuration(values)
          begin
            current_config = Utils::Archiver.find_configuration(Connection.config, Utils::Archiver::CONFIG_NAME)
            if current_config
              config = current_config.update_replace(values)
            else
              config = Utils::Archiver.create_configuration(Connection.config, Utils::Archiver::CONFIG_NAME, values, maintain_history: true)
            end

            callback_error = config.test_and_return_errors
            if callback_error.any?
              error_string = ''
              callback_error.each do |method, error|
                error_string << ', ' unless error_string.empty?
                error_string << "#{method}: #{error}"
              end
              raise Configh::ConfigValidationError, error_string
            end

          rescue Configh::ConfigInitError, Configh::ConfigValidationError => e
            raise APIClientError.new("Invalid archive config. #{e}", markup: Utils::Archiver.edit_configuration(values))
          end

          config.serialize['values']
        end

        def get_archive_configuration
          config = Utils::Archiver.find_configuration(Connection.config, Utils::Archiver::CONFIG_NAME)
          config.nil? ? nil : config.serialize['values']
        end

        def get_workflows
          Actions::WorkflowSet.for_admin( Connection.config, logger: @logger ).list_workflows
        end

        def with_workflow( workflow_name )
          raise APIClientError.new('Provide a workflow name') if workflow_name.nil? || workflow_name.empty?
          wf_set = Actions::WorkflowSet.for_admin( Connection.config, logger: @logger )
          wf = wf_set.get_workflow( workflow_name )
          raise APIClientError.new( "Workflow #{workflow_name} not found" ) unless wf
          yield wf
        end

        def get_workflow_status( workflow_name )
          with_workflow( workflow_name ) { |wf| wf.status }
        end

        def new_workflow
          Actions::Workflow.defined_parameters.collect{ |p| p.to_hash }
        end

        def create_workflow( config_values )
          wf_set = Actions::WorkflowSet.for_admin(Connection.config)
          wf_set.create_workflow(config_values)
        rescue Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message,
                                    markup: Actions::Workflow.edit_configuration( config_values, creating_in: Connection.config ))
        end

        def run_workflow( workflow_name )
          with_workflow(workflow_name){ |wf| wf.run }
        rescue Actions::WorkflowActivationError => e
          raise APIClientError.new( e.message )
        end

        def stop_workflow( workflow_name )
          with_workflow(workflow_name) do |wf|
            begin
              wf.stop
            rescue Actions::WorkflowDocumentsInProcessError => e
              return wf.status
            end
          end
        end

        def import_workflow(data)
          error_prefix = 'Unable to import workflow.'
          raise APIClientError, "#{error_prefix} Missing JSON data." unless [Hash, Array].include? data.class

          raise APIClientError, %Q{#{error_prefix} Missing {"workflow": {"name": "<name_goes_here>"}} section.} unless data.is_a?(Hash) && data.key?('workflow') && data['workflow'].is_a?(Hash) && data['workflow'].key?('name')

          wf_name = data.dig('workflow', 'name')
          raise APIClientError, "#{error_prefix} Workflow name cannot be blank." if  wf_name.to_s.strip.empty?

          if get_workflows.map { |wf| wf['name'].downcase }.include? wf_name.downcase
            with_workflow(wf_name) do |wf|
              raise APIClientError, "#{error_prefix} Workflow #{wf_name.inspect} is still running." if wf.status['run_mode'] != Status::STOPPED
            end
          else
            begin
              create_workflow('workflow'=>{'name'=>wf_name})
            rescue => e
              raise APIClientError, "#{error_prefix} Failed to create workflow #{wf_name.inspect}: #{e}"
            end
          end

          raise APIClientError, "#{error_prefix} Workflow JSON data missing actions." if !data['actions'].is_a?(Array) || data['actions'].empty?

          data['actions'].each do |action|
            action_name = action.dig('action', 'name')
            action_type = action['type']

            if action_name.to_s.strip.empty? && action_type.to_s.strip.empty?
              raise APIClientError, "#{error_prefix} One or more actions are missing both type and name."
            elsif action_name.to_s.strip.empty?
              raise APIClientError, "#{error_prefix} Action type #{action_type.inspect} is missing name."
            elsif action_type.to_s.strip.empty?
              raise APIClientError, "#{error_prefix} Action #{action_name.inspect} is missing type."
            end
          end

          begin
            existing_actions = get_workflow_actions(wf_name)&.map { |a| a['name'] }
          rescue
            existing_actions = []
          end

          # TODO ARM-759 retire any existing workflow actions that are not part of the import
          import_actions = data['actions'].map { |a| a.dig('action', 'name') }
          extra_actions  = existing_actions.map { |a| a.downcase } - import_actions.map { |a| a.downcase }
          raise APIClientError, "#{error_prefix} The following actions exist for #{wf_name.inspect} but are not part of the import: #{extra_actions.sort.join(', ')}" unless extra_actions.empty?

          data['actions'].each do |action|
            action_name = action.dig('action', 'name')
            action_type = action.delete('type')

            action['action']['active']   = false
            action['action']['workflow'] = wf_name

            if existing_actions.include? action_name.downcase
              begin
                action['type'] = action_type
                update_workflow_action_config(wf_name, action_name, action)
              rescue => e
                raise APIClientError, "#{error_prefix} Action #{action_name.inspect} was unable to be updated: #{e}"
              end
            else
              begin
                create_workflow_action_config(wf_name, action_type, action)
              rescue => e
                raise APIClientError, "#{error_prefix} Action #{action_name.inspect} was unable to be created: #{e}"
              end
            end
          end

          {
            'workflow' => get_workflows.find { |wf| wf['name'].downcase == wf_name.downcase },
            'actions'  => import_actions
          }
        end

        def export_workflow(wf_name = nil)
          output = []

          wfs_to_export =
            if wf_name
              _wf_name = get_workflows.find { |wf| wf['name'].downcase == wf_name.downcase }
              raise APIClientError, 'Workflow does not exist.' unless _wf_name
              [_wf_name['name']]
            else
              get_workflows.map { |wf| wf['name'] }
            end

          wfs_to_export.each do |wf|
            wf_output = {
              'workflow' => {
                'name'     => wf,
                'exported' => Time.now.utc,
                'versions' => Armagh::Status::LauncherStatus.find_all(raw: true)&.first&.[]('versions') || 'none available'
              },
              'actions' => []
            }
            get_workflow_actions(wf).each do |action|
              config = get_workflow_action_config(wf, action['name'])
              raise "Action #{action['name'].inspect} is invalid and will not export." unless config
              config['action'].delete('active')
              config['action'].delete('workflow')
              _config = {'type' => config.delete('type')}
              _config.merge! config
              wf_output['actions'] << _config
            end

            output << wf_output
          end

          JSON.pretty_generate(output.size == 1 ? output.first : output)
        rescue => e
          raise APIClientError, "Unable to export workflow #{wf_name.inspect}: #{e}"
        end

        def get_action_super(type)
          raise "Action type must be a Class.  Was a #{type}." unless type.is_a?(Class)
          Utils::ActionHelper.get_action_super(type)
        end

        def get_defined_actions
          actions = {}
          Actions.defined_actions.each do |action|
            type = get_action_super(action)
            actions[type] ||= []
            actions[type] << { 'name' => action.to_s, 'description' => action.description }
          end
          actions.sort.to_h
        end

        def get_workflow_actions( workflow_name )
          with_workflow(workflow_name){ |wf| wf.action_statuses}
        end

        def get_workflow_action_status( workflow_name, action_name )
          with_workflow(workflow_name){ |wf| wf.action_status(action_name)}
        rescue Actions::ActionFindError => e
          raise APIClientError.new(e.message)
        end

        def new_workflow_action_config( workflow_name, type )
          with_workflow(workflow_name){ |wf| wf.new_action_config( type ) }
        rescue Actions::ActionFindError, Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message )
        end

        def create_workflow_action_config( workflow_name, type, action_config )
          with_workflow(workflow_name){ |wf|
            wf.create_action_config( type, action_config )
            serialize_edit_action_config(wf.edit_action_config( action_config.dig('action','name')))
          }
        rescue Actions::ActionConfigError, Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message, markup: (e.respond_to?(:config_markup) ? serialize_edit_action_config(e.config_markup ): nil) )
        end

        def get_workflow_action_description( workflow_name, action_name )
          with_workflow(workflow_name){ |wf| serialize_edit_action_config(wf.edit_action_config( action_name ))}
        rescue Actions::ActionFindError, Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message )
        end

        def get_workflow_action_config(workflow_name, action_name)
          with_workflow(workflow_name) {|wf| wf.get_action_config(action_name)}
        end

        def update_workflow_action_config( workflow_name, action_name, action_config)
          with_workflow(workflow_name){ |wf|
            wf.update_action_config( wf.type( action_name ), action_config )
            serialize_edit_action_config(wf.edit_action_config( action_name ))
          }
        rescue Actions::ActionConfigError, Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message, markup: (e.respond_to?(:config_markup) ? serialize_edit_action_config(e.config_markup) : nil) )
        end

        def serialize_edit_action_config( edit_action_config )
          edit_action_config['type'] = edit_action_config['type'].to_s
          edit_action_config['supertype'] = constant(edit_action_config['type']).superclass.to_s
          edit_action_config
        end

        private def get_action_class_from_type(type)
          Actions.defined_actions.each do |defined|
            next unless defined.to_s == type.to_s
            return defined
          end
          raise APIClientError, "Action type #{type} does not exist"
        end

        def get_action_test_callbacks(type)
          type_class = get_action_class_from_type(type)
          defined_callbacks = []
          type_class.defined_group_test_callbacks.each do |callback|
            defined_callbacks << {
              group:  callback.group,
              class:  type_class,
              method: callback.callback_method
            }
          end
          defined_callbacks
        end

        def invoke_action_test_callback(data)
          type_class  = get_action_class_from_type(data['type'])
          group       = data['group']
          method      = data['method'].to_sym
          test_config = {group => data['test_config']}

          defined_params = type_class.defined_parameters
          encoded_params = defined_params.select { |p| p.type == 'encoded_string' }
          encoded_params.each do |p|
            plain_value = test_config.dig(group, p.name)
            next unless plain_value
            encoded_value = Configh::DataTypes::EncodedString.from_plain_text(plain_value)
            test_config[group][p.name] = encoded_value
          end

          begin
            config = type_class.create_configuration([], 'test_callback', test_config, test_callback_group: group)
          rescue => e
            return "Failed to instantiate test configuration: #{e.message}"
          end

          type_class.send(method, config)
        end

        def get_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
          Document
              .find_many_by_ts_range_read_only( doc_type, begin_ts, end_ts, start_index, max_returns )
              .to_a
        end

        def get_document( doc_id, doc_type )
          Document.find_one_by_document_id_type_state_read_only( doc_id, doc_type, Documents::DocState::PUBLISHED ).to_hash
        end

        def get_failed_documents
          Document.find_all_failures_read_only.collect{ |d| d.to_hash }
        end

        def get_version
          Launcher.get_versions(@logger, @gem_versions)
        end

        def get_users
          Authentication::User.find_all
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def get_user(id)
          find_user id
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def create_user(fields)
          Authentication::User.create(username: fields['username'], password: fields['password'], name: fields['name'], email: fields['email'])
        rescue Authentication::User::UserError, Armagh::Utils::Password::PasswordError => e
          raise APIClientError, e.message
        end

        def update_user_by_id(id, fields)
          user = Authentication::User.update(internal_id: id, username: fields['username'], password: fields['password'], name: fields['name'], email: fields['email'])
          raise APIClientError.new("User with ID #{id} not found.") unless user
          user
        rescue Authentication::User::UserError, Armagh::Utils::Password::PasswordError => e
          raise APIClientError, e.message
        end

        def update_user(user, fields)
          user.update(username: fields['username'], password: fields['password'], name: fields['name'], email: fields['email'])
          user.save
          user
        rescue Authentication::User::UserError, Armagh::Utils::Password::PasswordError => e
          raise APIClientError, e.message
        end

        def delete_user(id)
          user = find_user id
          user.delete
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_join_group(user_id, group_id, remote_user)
          user = find_user user_id
          group = find_group group_id

          new_roles = group.roles - user.all_roles.values.flatten.uniq
          protect_add_roles(remote_user, new_roles, "Cannot add user #{user_id} to group #{group_id}")

          user.join_group group
          user.save
          true
        rescue Authentication::User::UserError, Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def user_leave_group(user_id, group_id, remote_user)
          user = find_user user_id
          group = find_group group_id

          roles = user.all_roles
          roles.delete(group.name)
          lost_roles = group.roles - roles.values.flatten.uniq

          protect_remove_roles(remote_user, lost_roles, "Unable to remove user #{user_id} from group #{group_id}")

          user.leave_group group
          user.save
          true
        rescue Authentication::User::UserError, Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def user_add_role(user_id, role_key, remote_user)
          user = find_user user_id
          role = find_role role_key

          new_roles = [role] - user.all_roles.values.flatten.uniq
          protect_add_roles(remote_user, new_roles, "Cannot add role #{role.name} to user #{user_id}")

          user.add_role role
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_remove_role(user_id, role_key, remote_user)
          user = find_user user_id
          role = find_role role_key

          roles = user.all_roles
          roles['self'].delete(role)
          lost_roles = [role]- roles.values.flatten.uniq

          protect_remove_roles(remote_user, lost_roles, "Unable to remove role #{role_key} from user #{user_id}")

          user.remove_role(role)
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_has_document_role(user, doctype = nil)
          role = Authentication::Role.find_from_published_doctype(doctype) if doctype
          role ||= Authentication::Role::USER
          raise Authentication::AuthenticationError, "User #{user.username} does not have the required role to access #{doctype} documents." unless user.has_role? role
          true
        end

        def user_reset_password(user_id, remote_user)
          user = find_user user_id
          protect_reset_password(remote_user, user.all_roles.values.flatten.uniq, "Cannot reset password for #{user_id}")
          user.reset_password
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_lock_out(user_id)
          user = find_user user_id
          user.lock_out
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_remove_lock_out(user_id)
          user = find_user user_id
          user.remove_lock_out
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_enable(user_id)
          user = find_user user_id
          user.enable
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def user_disable(user_id)
          user = find_user user_id
          user.disable
          user.save
          true
        rescue Authentication::User::UserError => e
          raise APIClientError, e.message
        end

        def get_groups
          Authentication::Group.find_all
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def get_group(id)
          find_group id
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def create_group(fields)
          Authentication::Group.create(name: fields['name'], description: fields['description'])
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def update_group(id, fields)
          group = Authentication::Group.update(id: id, name: fields['name'], description: fields['description'])
          raise APIClientError.new("Group with ID #{id} not found.") unless group
          group
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def group_add_role(group_id, role_key, remote_user)
          group = find_group group_id
          role = find_role role_key

          protect_add_roles(remote_user, [role], "Cannot add role #{role.name} to group #{group_id}")

          group.add_role role
          group.save
          true
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def group_remove_role(group_id, role_key, remote_user)
          group = find_group group_id
          role = find_role role_key

          protect_remove_roles(remote_user, [role], "Unable to remove role #{role.name} from group #{group_id}")

          group.remove_role(role)
          group.save
          true
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def group_add_user(group_id, user_id, remote_user)
          user = find_user user_id
          group = find_group group_id

          new_roles = group.roles - user.all_roles.values.flatten.uniq
          protect_add_roles(remote_user, new_roles, "Cannot add user #{user_id} to group #{group_id}")

          group.add_user user
          group.save
          true
        rescue Authentication::User::UserError, Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def group_remove_user(group_id, user_id, remote_user)
          user = find_user user_id
          group = find_group group_id

          roles = user.all_roles
          roles.delete(group.name)
          lost_roles = group.roles - roles.values.flatten.uniq

          protect_remove_roles(remote_user, lost_roles, "Unable to remove user #{user_id} from group #{group_id}")

          group.remove_user user
          group.save
          true
        rescue Authentication::User::UserError, Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def delete_group(id, remote_user)
          group = find_group id
          protect_remove_roles(remote_user, group.roles, "Unable to remove group #{id}")
          group.delete
          true
        rescue Authentication::Group::GroupError => e
          raise APIClientError, e.message
        end

        def get_roles
          Authentication::Role.all
        end

        def trigger_collect(action_name)
          workflow_set = Actions::WorkflowSet.for_admin(Connection.config)
          workflow_set.trigger_collect(action_name)
        rescue Armagh::Actions::TriggerCollectError => e
          raise APIClientError, e.message
        end

        def update_password(user, password)
          user.password = password
          user.save
          true
        rescue Authentication::User::UserError, Utils::Password::PasswordError => e
          raise APIClientError, e.message
        end

        private def find_user(user_id)
          user = Authentication::User.find_one_by_internal_id(user_id)
          raise APIClientError.new("User with ID #{user_id} not found.") unless user
          user
        end

        private def find_group(group_id)
          group = Authentication::Group.find_one_by_internal_id(group_id)
          raise APIClientError.new("Group with ID #{group_id} not found.") unless group
          group
        end

        private def find_role(role_key)
          role = Authentication::Role.find(role_key)
          raise APIClientError.new("Role '#{role_key}' not found.") unless role
          role
        end

        private def protect_reset_password(remote_user, roles, message)
          missing_roles = roles.reject{|role| remote_user.has_role?(role)}
          raise APIClientError, "#{message}. The user has the following roles, which you don't have: #{missing_roles.collect{|r|r.name}.join(', ')}." unless missing_roles.empty?
        end

        private def protect_add_roles(remote_user, roles, message)
          missing_roles = roles.reject{|role| remote_user.has_role?(role)}
          raise APIClientError, "#{message}. Doing so would grant the following roles, which you don't have: #{missing_roles.collect{|r|r.name}.join(', ')}." unless missing_roles.empty?
        end

        private def protect_remove_roles(remote_user, roles, message)
          missing_roles = roles.reject{|role| remote_user.has_role?(role)}
          raise APIClientError, "#{message}. Doing so would remove the following roles, which you don't have: #{missing_roles.collect{|r|r.name}.join(', ')}." unless missing_roles.empty?
        end

        def get_alerts( count_only: false, workflow: nil, action: nil )
          Armagh::Logging::Alert.get_counts( workflow: workflow, action: action )
        end
      end
    end
  end
end
