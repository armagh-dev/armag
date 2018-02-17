# Copyright 2018 Noragh Analytics, Inc.
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
require 'armagh/logging'

require_relative '../../configuration/file_based_configuration.rb'
require_relative './cluster_server.rb'
require_relative '../../connection'
require_relative '../../actions/gem_manager'

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
      
        DEFAULTS = {
          'ip'             => '127.0.0.1',
          'port'           => 4598,
          'key_filepath'   => '/home/armagh/.ssl/privkey.pem',
          'cert_filepath'  => '/home/armagh/.ssl/cert.pem'
        }
      
        def initialize
          @logger = Logging.set_logger('Armagh::ResourceAdminAPI')

          Connection.require_connection(@logger)

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

          @gem_versions = Actions::GemManager.instance.activate_installed_gems(@logger)
        end
      
        def using_ssl?
          ( @config['key_filepath'] and (!@config['key_filepath'].empty?) and @config['cert_filepath'] and (!@config['cert_filepath'].empty?))
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
      
      