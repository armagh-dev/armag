require 'singleton'
require_relative '../../logging'
require_relative '../../configuration/file_based_configuration.rb'
require_relative './cluster_server.rb'

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
      
        #LOG_LOCATION = '/var/log/armagh/resource_admin_api.log'
      
        DEFAULTS = {
          'ip'             => '127.0.0.1',
          'port'           => 4598,
          'key_filepath'   => '/home/armagh/.ssl/privkey.pem',
          'cert_filepath'  => '/home/armagh/.ssl/cert.pem'
        }
      
        def initialize
          @logger = Logging.set_logger('Armagh::ResourceAdminAPI')

          begin
            config      = Configuration::FileBasedConfiguration.load( self.class.to_s )
          rescue => e
            Logging.dev_error_exception(@logger, e, "Invalid file based configuration for #{self.class.to_s}.  Reverting to default.")
            config = {}
          end

          @config = DEFAULTS.merge config
          @config.delete 'key_filepath' unless File.exists? @config[ 'key_filepath' ]
          @config.delete 'cert_filepath' unless File.exists? @config[ 'cert_filepath' ]
          
          @config.each do |k,v|
            instance_variable_set "@#{k}", v
          end
          
        end
      
        def using_ssl?
          ( @config['key_filepath'] and (!@config['key_filepath'].empty?) and @config['cert_filepath'] and (!@config['cert_filepath'].empty?))
        end
      
        def authenticate_and_authorize user, password
          # TODO - replace admin resource api authenticate_and_authorize with LDAP, verify resource admin privileges
          true
        end
      
        def root_directory
          File.join( __dir__, 'www_root' )
        end
          
        def report_profile
          ClusterServer.new( '127.0.0.1', @logger ).report_profile
        end
      end
    end
  end
end
      
      