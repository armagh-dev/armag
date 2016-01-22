require 'singleton'
require_relative '../../logging/global_logger.rb'
require_relative '../../configuration/file_based_configuration.rb'

module Armagh
  module Admin
    module Resource
    
      class API
        include Singleton

        attr_accessor :ip,
                      :port,
                      :key_filepath,
                      :cert_filepath,
                      :verify_peer,
                      :cluster_design_filepath,
                      :logger
      
        LOG_LOCATION = '/var/log/armagh/resource_admin_api.log'
      
        DEFAULTS = {
          'ip'             => '127.0.0.1',
          'port'           => 4598,
          'key_filepath'   => '/home/armagh/.ssl/privkey.pem',
          'cert_filepath'  => '/home/armagh/.ssl/cert.pem'
        }
      
        def initialize
        
          @logger     = Logging::GlobalLogger.new( 'ResourceAdminAPI', LOG_LOCATION, 'daily' )
          @logger.is_a_resource_log = true
        
          config_dir  = ENV[ 'ARMAGH_CONFIG' ] || File.join( File::SEPARATOR, 'etc', 'armagh')
          config_path = File.join( config_dir, 'resource_admin_api_config.json' )
          config      = Configuration::FileBasedConfiguration.load( config_path, DEFAULTS )
          config.delete 'key_filepath' unless File.exists? config[ 'key_filepath' ]
          config.delete 'cert_filepath' unless File.exists? config[ 'cert_filepath' ]
          Configuration::FileBasedConfiguration.assign( config, self )        
        
        end
      
        def using_ssl?
          ( @key_filepath and (!@key_filepath.empty?) and @cert_filepath and (!@cert_filepath.empty?))
        end
      
        def authenticate_and_authorize user, password
          # TODO - replace with LDAP-based authentication, verify admin privileges
          true
        end
      
        def root_directory
          File.join( __dir__, 'www_root' )
        end
            
      end
    end
  end
end
      
      