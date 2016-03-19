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
      class PositiveInteger < Integer
        def self.valid?(value)
          value.is_a?(Integer) && value.positive?
        end
      end

      attr_reader :last_config_timestamp, :default_config

      DEFAULT_CONFIG = {
          'log_level' => 'debug',
          'timestamp' => Time.utc(0)
      }

      VALID_FIELDS = {
          'log_level' => String,
          'timestamp' => Time
      }

      VALID_LOG_LEVELS = %w(fatal error warn info debug)

      def initialize(type, logger)
        @type = type
        @logger = logger
        @default_config = self.class.default_config
      end

      # Gets the latest configuration.  If the last retrieved configuration is the newest or the retrieved config is invalid, this returns nil.
      def get_config
        #TODO ConfigManager#get_config: Setup an Index - Connection.config.indexes.create_one('type')
        begin
          db_config = Connection.config.find('type' => @type).projection({'type' => 0, '_id' => 0}).limit(1).first || {}
        rescue => e
          @logger.error "Problem getting #{@type} configuration."
          # TODO Fix split logging in ConfigManager#get_config
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

        return nil unless new_config? config

        validated_config = validate_config config
        validated_config
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
        VALID_FIELDS.merge self::VALID_FIELDS
      end

      def self.default_config
        DEFAULT_CONFIG.merge self::DEFAULT_CONFIG
      end

      def self.validate(config)
        errors = []
        warnings = []

        default_config = self.default_config

        unknown_fields = config.keys - valid_fields.keys

        if unknown_fields.any?
          warnings << "The following settings were configured but are unknown: #{unknown_fields}."
        end

        valid_fields.each do |field, type|
          config_field = config[field]
          if config_field.nil?
            if default_config[field]
              warnings << "'#{field}' does not exist in the configuration.  Will use the default value of #{default_config[field]}."
            else
              errors << "'#{field}' does not exist in the configuration."
            end
          elsif !config_field.is_a?(type) && !(type == PositiveInteger && PositiveInteger.valid?(config_field))
            errors << "'#{field}' must be a #{type} object.  Was a #{config_field.class.name}."
          end
        end

        log_level = config['log_level']
        warnings << "'log_level' must be #{VALID_LOG_LEVELS}.  Was '#{log_level}'.  Will use the default value of '#{default_config['log_level']}'." unless VALID_LOG_LEVELS.include?(log_level)

        {'valid' => errors.empty?, 'errors' => errors, 'warnings' => warnings}
      end

      def self.format_validation_results(result)
        state = result['valid'] ? 'valid' : 'invalid'
        warnings = result['warnings']
        errors = result['errors']

        msg = "The configuration is #{state}."

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

      private def new_config?(config)
        new = true
        if config['timestamp'].is_a?(Time) && @last_config_timestamp
          if config['timestamp'] < @last_config_timestamp
            @logger.warn "#{@type} configuration received that was older than last applied."
            new = false
          elsif config['timestamp'] == @last_config_timestamp
            # We are up to date
            new = false
          end
        end
        new
      end

      private def validate_config(config)
        validation_result = self.class.validate(config)

        if validation_result['valid']
          @logger.warn "#{@type} configuration validation is usable but had warnings:\n #{self.class.format_validation_results(validation_result)}" if validation_result['warnings'].any?
          @last_config_timestamp = config['timestamp']
          config['log_level'] = get_log_level(config['log_level'])
        else
          if @last_config_timestamp
            config = nil
            msg  = 'Keeping current configuration.'
          else
            config = @default_config.dup
            config['log_level'] = get_log_level(config['log_level'])
            msg = 'Reverting to default configuration.'
          end
          @logger.error "#{@type} configuration validation failed:\n #{self.class.format_validation_results(validation_result)}\n\n#{msg}"
        end
        config
      end
    end
  end
end
