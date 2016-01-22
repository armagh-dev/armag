require 'oj'

module Armagh
  module Configuration
    module FileBasedConfiguration
       
      def self.load( from_filepath, using_defaults = {} )
        
        config = using_defaults
        if File.exists? from_filepath
          begin
            config.merge!( Oj.load( File.read from_filepath ))
          rescue => e
            @logger.warn "Configuration file at #{ from_filepath } could not be parsed.  Using defaults."
          end
        end
      
        config
      end
    
      def self.assign( config_hash, to_object )
      
        config_hash.each do |key, value|
          to_object.instance_variable_set "@#{ key }", value
        end
      end
    
      def self.write( to_filepath, config_hash )
      
        begin
          File.open( to_filepath, 'w' ) do |f|
            f << Oj.dump( config_hash )
          end
        rescue  => e
          @logger.warn "Unable to write configuration back to #{to_filepath}. Error: #{ e.message }\n#{ e.backtrace.first(5).join("\n")}"
        end
      end
    end
  end
end
    