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
require_relative '../../utils/collection_trigger'


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

      class API
        include Singleton

        attr_accessor :ip,
                      :port,
                      :key_filepath,
                      :cert_filepath,
                      :verify_peer,
                      :cluster_design_filepath,
                      :logger

        LOG_LOCATION = '/var/log/armagh/application_admin_api.log'

        DEFAULTS = {
            'ip'             => '127.0.0.1',
            'port'           => 4599,
            'key_filepath'   => '/home/armagh/.ssl/privkey.pem',
            'cert_filepath'  => '/home/armagh/.ssl/cert.pem'
        }

        def initialize
          @logger = Logging.set_logger('Armagh::ApplicationAdminAPI')

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

        def authenticate_and_authorize(user, password)
          # TODO - admin api, replace authenticate_and_authorize with LDAP call, verify admin privileges
          true
        end

        def root_directory
          File.join( __dir__, 'www_root' )
        end

        def get_status
          Connection.status.find().to_a
        end

        def create_or_update_launcher_configuration( params )
          begin
            config = nil
            current_config = get_launcher_configuration
            if current_config
              config = current_config.update_replace( { 'launcher' => params })
            else
              config = Launcher.create_configuration( Connection.config, Launcher.config_name, {'launcher' => params}, maintain_history: true )
            end
          rescue Configh::ConfigInitError, Configh::ConfigValidationError => e
            raise APIClientError.new( 'Invalid launcher config', markup: Launcher.edit_configuration( { 'launcher' => params}))
          end
          config.serialize['values']
        end

        def get_launcher_configuration
          Launcher.find_configuration( Connection.config, Launcher.config_name )
        end

        def get_workflows
          Actions::WorkflowSet.for_admin( Connection.config ).list_workflows
        end

        def with_workflow( workflow_name )
          raise APIClientError.new('Provide a workflow name') if workflow_name.nil? || workflow_name.empty?
          wf_set = Actions::WorkflowSet.for_admin( Connection.config )
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
          workflow = wf_set.create_workflow(config_values)
        rescue Actions::WorkflowConfigError => e
          raise APIClientError.new( e.message,
                                    markup: Actions::Workflow.edit_configuration( config_values, creating_in: Connection.config ))
        end

        def run_workflow( workflow_name )
          with_workflow(workflow_name){ |wf| wf.run }
        rescue Actions::WorkflowActivationError => e
          raise APIClientError.new( e.message )
        end

        def finish_workflow( workflow_name )
          with_workflow(workflow_name){ |wf| wf.finish}
        rescue Actions::WorkflowActivationError => e
          raise APIClientError.new( e.message )
        end

        def stop_workflow( workflow_name )
          with_workflow(workflow_name){ |wf| wf.stop}
        rescue Actions::WorkflowActivationError => e
          raise APIClientError.new( e.message )
        end

        def get_action_super(type)
          raise "Action type must be a Class.  Was a #{type}." unless type.is_a?(Class)
          unless Actions.defined_actions.include?(type)
            raise "Unexpected action type: #{type}"
          end

          superclass_name = type.superclass.to_s

          superclass_name.sub!(/^Armagh::Actions::/, '') ? superclass_name : get_action_super(type.superclass)
        end

        def get_defined_actions
          actions = {}
          Actions.defined_actions.each do |action|
            type = get_action_super(action)
            actions[type] ||= []
            actions[type] << action.to_s
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

        def get_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
          Document
              .find_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
              .to_a
        end

        def get_document( doc_id, doc_type )
          Document.find( doc_id, doc_type, Documents::DocState::PUBLISHED, raw: true )
        end

        def get_failed_documents
          Document.failures(raw: true)
        end

        def get_version
          Launcher.get_versions(@logger, @gem_versions)
        end

        def trigger_collect(action_name)
          workflow_set = Actions::WorkflowSet.for_admin(Connection.config)
          workflow_set.trigger_collect(action_name)
        rescue Armagh::Actions::TriggerCollectError => e
          raise APIClientError, e.message
        end
      end
    end
  end
end
