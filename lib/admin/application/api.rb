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

require_relative '../../logging'
require_relative '../../configuration/file_based_configuration'
require_relative '../../launcher/launcher'
require_relative '../../actions/workflow'
require_relative '../../models/document'
require_relative '../../actions/gem_manager'
require_relative '../../utils/collection_trigger'


module Armagh
  module Admin
    module Application
    
      class APIError < StandardError; end
      
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
            current_config = get_launcher_configuration
            if current_config
              current_config.update_replace( { 'launcher' => params })
            else
              Launcher.create_configuration( Connection.config, Launcher.config_name, {'launcher' => params}, maintain_history: true )
            end
            config = get_launcher_configuration.serialize  # weak test, but short lived.
            config[ '__message' ] = 'Configuration successful.'
          rescue => e
            Logging.dev_error_exception(@logger, e, 'Error creating launcher configuration')
            config = params
            config[ '__message' ] = e.message
          end
          return config
        end
        
        def get_launcher_configuration
          Launcher.find_configuration( Connection.config, Launcher.config_name )
        end
        
        def get_document_counts    
          Models::Document.count_working_by_doctype
        end
        
        def create_action_configuration( configuration_hash )
          action_class_name = configuration_hash[ 'action_class_name' ]
      
          workflow = Actions::Workflow.new( @logger, Connection.config )
          workflow.create_action( action_class_name, configuration_hash )
            
        end
        
        def update_action_configuration( configuration_hash )
          action_class_name = configuration_hash[ 'action_class_name' ]
          
          workflow = Actions::Workflow.new( @logger, Connection.config )
          workflow.update_action( action_class_name, configuration_hash )
        end
        
        def activate_actions( actions )
          workflow = Actions::Workflow.new( @logger, Connection.config )
          workflow.activate_actions( actions )
        end
          
        def get_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
          Models::Document
            .find_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
            .to_a
        end
        
        def get_document( doc_id, doc_type )
          Models::Document.find( doc_id, doc_type, Documents::DocState::PUBLISHED, raw: true )
        end

        def get_failed_documents
          Models::Document.failures(raw: true)
        end

        def get_version
          Launcher.get_versions(@logger, @gem_versions)
        end

        def get_action_configs
          workflow = Actions::Workflow.new(@logger, Connection.config)
          actions = workflow.get_all_actions

          actions.collect do |a|
            h = a.serialize
            h['values'].merge('action_class_name' => h['type'])
          end
        end

        def get_action_config(action_name)
          workflow = Actions::Workflow.new(@logger, Connection.config)
          action = workflow.get_action(action_name)
          if action
            h = action.serialize
            h['values'].merge('action_class_name' => h['type'])
          else
            nil
          end
        end

        def trigger_collect(action_name)
          workflow = Actions::Workflow.new(@logger, Connection.config)
          action_config = workflow.get_action(action_name)
          if action_config
            action_class = action_config.__type
            if action_class < Actions::Collect
              trigger = Utils::CollectionTrigger.new(workflow)
              trigger.trigger_individual_collection(action_config)
              true
            else
              false
            end
          else
            false
          end
        end
      end         
    end
  end
end
      
      