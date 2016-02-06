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
    