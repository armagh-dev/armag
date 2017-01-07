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

require 'oj'
require 'fileutils'
require_relative '../errors'

module Armagh
  module Configuration
    module FileBasedConfiguration

      CONFIG_DIRS = [ '/etc/armagh', File.join( __dir__, '..') ].collect{|p| File.absolute_path(p)}

      def self.filepath
        CONFIG_DIRS.each do |dir|
          fp = File.join( dir, 'armagh_env.json' )
          return fp if File.file?( fp )
        end
        raise Errors::ConfigurationError, "Can't find the armagh_env.json file in #{CONFIG_DIRS.join(', ')}"
      end

      def self.load(key)
        config = {}
        begin
          config_fp  = self.filepath
          app_config = Oj.load( File.read config_fp ) || {}
          if app_config.has_key? key
            config = app_config[key]
          else
            raise Errors::ConfigurationError, "Configuration file #{config_fp} does not contain '#{key}'."
          end
        rescue Errors::ConfigurationError
          raise
        rescue
          raise Errors::ConfigurationError, "Configuration file #{ config_fp } could not be parsed."
        end
        config
      end
    end
  end
end
    