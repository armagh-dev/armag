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

require 'singleton'

require_relative '../logging/global_logger'

module Armagh
  module Configuration
    class LauncherConfig
      include Singleton

      LOG_LOCATION = '/var/log/armagh/launcher_config.log'

      DEFAULT_CONFIG = {
          'num_agents' => 1,
          'checkin_frequency' => 60,
          'log_level' => Logger::DEBUG,
          'available_actions' => {},
          'timestamp' => Time.new(0)
      }

      def initialize
        @logger = Logging::GlobalLogger.new('LauncherConfig', LOG_LOCATION, 'daily')
      end

      def self.get_config
        LauncherConfig.instance.get_config
      end

      def get_config
        begin
          #TODO Setup an Index - Connection.config.indexes.create_one('type')
          # TODO Each machine can have it's own config
          #  So we need the following configs
          #  Default, Generic Launcher (system wide), specific launcher
          #   And a per-server config that overrides the generic
          db_config = Connection.config.find('type' => 'launcher').limit(1).first || {}
        rescue => e
          @logger.error 'Problem getting centralized launcher armagh config'
          @logger.error e
          db_config = {}
        end

        if db_config.empty?
          @logger.warn "No launcher configuration found.  Using default #{DEFAULT_CONFIG}"
        else
          missing = DEFAULT_CONFIG.keys - db_config.keys
          @logger.warn "Partial launcher configuration found.  Using default values for #{missing.join(', ')}" unless missing.empty?
        end

        db_config['log_level'] = get_log_level(db_config['log_level']) if db_config['log_level']

        config = DEFAULT_CONFIG.merge db_config

        @logger.level = config['log_level']

        @logger.debug "Launcher Config: #{config}"

        config
      end

      private def get_log_level(level)
        unless [Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR, Logger::FATAL].include? level
          @logger.error "Unknown log level from configuration: #{level}. Reverting to default"
          level = DEFAULT_CONFIG['log_level']
        end

        level
      end
    end
  end
end
