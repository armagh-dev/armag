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

require_relative 'config_manager'

module Armagh
  module Configuration
    class LauncherConfigManager < ConfigManager
      DEFAULT_CONFIG = {
          'num_agents' => 1,
          'checkin_frequency' => 5
      }

      VALID_FIELDS = %w(num_agents checkin_frequency)

      def initialize(logger)
        super('launcher', logger)
      end

      def self.validate(config)
        warnings = []
        errors = []

        base_valid = super

        warnings.concat base_valid['warnings']
        errors.concat base_valid['warnings']

        num_agents = config['num_agents']
        if num_agents
          errors << "'num_agents' must be a positive integer." unless num_agents.is_a?(Integer) && num_agents > 0
        else
          warnings << "num_agents' does not exist in the configuration.  Using default value of #{@default_config['num_agents']}."
        end

        checkin_frequency = config['checkin_frequency']
        if checkin_frequency
          errors << "'checkin_frequency' must be a positive integer." unless checkin_frequency.is_a?(Integer) && checkin_frequency > 0
        else
          warnings << "checkin_frequency' does not exist in the configuration.  Using default value of #{@default_config['checkin_frequency']}."
        end

        unknown_fields = config.keys - valid_fields

        if unknown_fields.any?
          warnings << "The following settings were configured but are unknown to the launcher: #{unknown_fields}"
        end

        {'valid' => errors.empty?, 'errors' => errors, 'warnings' => warnings}
      end
    end
  end
end
