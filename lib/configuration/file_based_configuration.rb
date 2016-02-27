# Copyright 2016 Noragh Analytics, Inc.
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

require 'oj'
require 'fileutils'

module Armagh
  module Configuration
    module FileBasedConfiguration
       
      def self.filepath
        
        config_dirs = [ '/etc', File.join( __dir__, '..') ]
        config_dirs.each do |dir|
          
          fp = File.join( dir, 'armagh_env.json' )
          return fp if File.exists?( fp )
        end
        raise "Can't find the armagh_env.json file in #{config_dirs.join(', ')}"
      end
       
      def self.load( key )
        
        config = {}
        begin
          config_fp  = self.filepath
          app_config = Oj.load( File.read config_fp ) || {}
          config     = app_config[ key ]
        rescue => e
          @logger.error "Configuration file #{ config_fp }could not be parsed.  Using defaults. Error: #{ e.message }"
        end
        config
      end
    
      def self.assign( config_hash, to_object )
      
        config_hash.each do |key, value|
          to_object.instance_variable_set "@#{ key }", value
        end
      end
    
    end
  end
end
    