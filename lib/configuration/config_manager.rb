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

require_relative '../connection'
require_relative '../logging/global_logger'

module Armagh
  module Configuration
    class ConfigManager

      attr_reader :last_config_timestamp

      DEFAULT_CONFIG = {
          'log_level' => 'debug',
          'timestamp' => Time.utc(0)
      }

      def initialize(type, logger)
        @type = type
        @logger = logger
        @default_config = DEFAULT_CONFIG.merge self.class::DEFAULT_CONFIG
      end

      # Gets the latest configuration.  If the last retrieved configuration is the newest, this returns nil.
      def get_config
        #TODO Setup an Index - Connection.config.indexes.create_one('type')
        begin
          db_config = Connection.config.find('type' => @type).limit(1).first || {}
        rescue => e
          @logger.error "Problem getting #{@type} configuration."
          @logger.error e
          db_config = {}
        end

        if db_config.empty?
          @logger.warn "No #{@type} configuration found.  Using default #{@default_config}"
        else
          missing = @default_config.keys - db_config.keys
          @logger.warn "Partial #{@type} configuration found.  Using default values for #{missing.join(', ')}" unless missing.empty?
        end

        config = @default_config.merge db_config
        config['log_level'] = get_log_level(config['log_level'])

        if @last_config_timestamp.nil?
          # First time getting a configuration
          @last_config_timestamp = config['timestamp']
          config
        elsif config['timestamp'] > @last_config_timestamp
          # Updated Config
          @last_config_timestamp = config['timestamp']
          config
        elsif config['timestamp'] < @last_config_timestamp
          # The config is older than the last one we received
          @logger.warn "#{@type} configuration received that was older than last applied."
          nil
        else
          # Do Nothing, We are up to date
          nil
        end
      end

      def get_log_level(level_str)
        case level_str.strip.downcase
          when 'fatal'
            Logger::FATAL
          when 'error'
            Logger::ERROR
          when 'warn'
            Logger::WARN
          when 'info'
            Logger::INFO
          when 'debug'
            Logger::DEBUG
          else
            @logger.error "Unknown log level #{level_str}. Reverting to default"
            Logger::DEBUG
        end
      end
    end
  end
end
