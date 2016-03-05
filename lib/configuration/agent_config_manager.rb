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
    class AgentConfigManager < ConfigManager
      DEFAULT_CONFIG = {
          'available_actions' => {},
      }

      VALID_FIELDS = ['available_actions']

      def initialize(logger)
        super('agent', logger)
      end

      def self.validate(config)
        warnings = []
        errors = []

        base_valid = super

        warnings.concat base_valid['warnings']
        errors.concat base_valid['errors']

        action_validation_result = Configuration::ActionConfigValidator.validate(config['available_actions'])
        warnings.concat action_validation_result['warnings']
        errors.concat action_validation_result['errors']

        unknown_fields = config.keys - valid_fields

        if unknown_fields.any?
          warnings << "The following settings were configured but are unknown to the launcher: #{unknown_fields}"
        end

        {
            'valid'     => errors.empty?,
            'errors'    => errors,
            'warnings'  => warnings
        }
      end
    end
  end
end
