# Copyright 2018 Noragh Analytics, Inc.
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

require 'configh'
require 'armagh/logging'

require_relative 'utility_action'
require_relative '../../connection'

module Armagh
  module Actions
    module UtilityActions

      class PurgeLogsUtilityAction < UtilityAction
        include Configh::Configurable

        define_parameter name: 'debug_age', type: 'positive_integer', required: true, description: 'Maximum age (in days) to keep debug messages.', default: 15, group: 'purge_logs'
        define_parameter name: 'info_age', type: 'positive_integer', required: true, description: 'Maximum age (in days) to keep info messages.', default: 30, group: 'purge_logs'
        define_parameter name: 'warn_age', type: 'positive_integer', required: true, description: 'Maximum age (in days) to keep warn messages.', default: 60, group: 'purge_logs'
        define_parameter name: 'error_age', type: 'positive_integer', required: true, description: 'Maximum age (in days) to keep error messages.', default: 120, group: 'purge_logs'

        LEVELS_TO_CLEAN = %w(debug info warn error)

        def run
          age_map = {
            'debug' => @config.purge_logs.debug_age,
            'info' => @config.purge_logs.info_age,
            'warn' => @config.purge_logs.warn_age,
            'error' => @config.purge_logs.error_age,
          }

          age_map.each do |base_level, max_age|
            max_timestamp = (DateTime.now - max_age).to_time.utc
            levels = Armagh::Logging.sublevels(base_level)

            Armagh::Connection.all_log_collections.each do |collection|
              collection.delete_many({'level' => {'$in' => levels} , 'timestamp' => {'$lte' => max_timestamp}})
            end
          end
        end
      end
    end
  end
end
