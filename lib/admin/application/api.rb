require 'singleton'

require_relative '../../logging'
require_relative '../../configuration/file_based_configuration'
require_relative '../../action/workflow'
require_relative '../../document/document'
require_relative '../../action/gem_manager'

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
          def @logger.<<( message )
            info( message )
          end

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
          
          gem_manager = Armagh::Actions::GemManager.new( @logger )
          gem_manager.activate_installed_gems
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
        
        def configure_launcher( params )
          config = Launcher.create_configuration( Connection.config, Launcher.config_name, params, maintain_history: true )
          config.__values
        end
        
        def get_document_counts    
          counts = Document.count_working_by_doctype
        end
        
        def create_action_configuration( configuration_hash )
          
          @logger.debug( 'lib/admin/application/api create_action_configuration' )
          @logger.debug( "... with configuration_hash #{ configuration_hash.inspect }")
          
          action_class_name = configuration_hash[ 'action_class_name' ]
      
          workflow = Actions::Workflow.new( @logger, Connection.config )
          workflow.create_action( action_class_name, configuration_hash )
            
        end
        
        def update_action_configuration( configuration_hash )
          
          action_class_name = configuration_hash[ 'action_class_name' ]
          
          workflow = Actions::Workflow.new( @logger, Connection.config )
          workflow.update_action( action_class_name, configuration_hash )
        end
          
      end         
    end
  end
end
      
      