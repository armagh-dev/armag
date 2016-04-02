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
          'checkin_frequency' => 60
      }

      VALID_FIELDS = {
          'num_agents' => NonNegativeInteger,
          'checkin_frequency' => PositiveInteger
      }

      def initialize(logger)
        super('launcher', logger)
      end

      def self.default_log_level
        logger = Log4r::Logger['Armagh::Application::Launcher'] || Log4r::Logger.new('Armagh::Application::Launcher')
        logger.levels[logger.level].downcase
      end

      def self.validate(config)
        warnings = []
        errors = []

        base_valid = super

        warnings.concat base_valid['warnings']
        errors.concat base_valid['errors']

        {'valid' => errors.empty?, 'errors' => errors, 'warnings' => warnings}
      end
    end
  end
end
