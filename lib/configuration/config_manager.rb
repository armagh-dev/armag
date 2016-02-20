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

      attr_reader :last_config_timestamp, :default_config

      DEFAULT_CONFIG = {
          'log_level' => 'debug',
          'timestamp' => Time.utc(0)
      }

      VALID_FIELDS = %w(log_level timestamp)

      def initialize(type, logger)
        @type = type
        @logger = logger
        @default_config = DEFAULT_CONFIG.merge self.class::DEFAULT_CONFIG
      end

      # Gets the latest configuration.  If the last retrieved configuration is the newest or the retrieved config is invalid, this returns nil.
      def get_config
        #TODO Setup an Index - Connection.config.indexes.create_one('type')
        begin
          db_config = Connection.config.find('type' => @type).limit(1).first || {}
          db_config.delete '_id'
          db_config.delete 'type'
        rescue => e
          @logger.error "Problem getting #{@type} configuration."
          # TODO Don't call error twice
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

        validation_result = self.class.validate config

        unless validation_result['valid']
          @logger.error "Validation failed: #{format_validation_results(validation_result)}\n.  Reverting to default configuration."
          config = @default_config.dup
        end

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
            default = @default_config['log_level']
            @logger.error "Unknown log level #{level_str}. Reverting to #{default}."
            get_log_level(default)
        end
      end

      def self.valid_fields
        VALID_FIELDS.concat self::VALID_FIELDS
      end

      def self.validate(config)
        errors = []
        warnings = []
        timestamp = config['timestamp']
        if timestamp
          errors << "'timestamp' must be a time object." unless timestamp.is_a?(Time)
        else
          warnings << "timestamp' does not exist in the configuration.  Using default value of #{@default_config['timestamp']}."
        end

        log_level = config['log_level']
        valid_levels = %w(fatal error warn info debug)
        if log_level
          warnings << "'log_level' must be #{valid_levels}.  Usind default value of #{@default_config['log_level']}" unless valid_levels.include?(log_level)
        else
          warnings << "log_level' does not exist in the configuration.  Using default value of #{@default_config['log_level']}."
        end

        {'valid' => errors.empty?, 'errors' => errors, 'warnings' => warnings}
      end

      def self.format_validation_results(result)
        state = result['valid'] ? 'valid' : 'invalid'
        warnings = result['warnings']
        errors = result['errors']

        msg = "The configuration is #{state}"

        if warnings.any?
          msg << "\n\nWarnings: "
          warnings.each do |warning|
            msg << "\n  #{warning}"
          end
        end

        if errors.any?
          msg << "\n\nErrors:"
          errors.each do |error|
            msg << "\n  #{error}"
          end
        end

        msg
      end
    end
  end
end
