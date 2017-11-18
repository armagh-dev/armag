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

require 'configh'
require_relative 'utility_action.rb'

module Armagh
  module Actions
    module UtilityActions

      class DBCleanUpUtilityAction < UtilityAction
        include Configh::Configurable

        def self.default_cron
          '* * * * *'
        end

        def run
          try_to_move_stopping_workflows_to_stopped
          reset_expired_locks
        end

        def try_to_move_stopping_workflows_to_stopped
          workflow_set = WorkflowSet.for_agent( Connection.config, logger: logger )
          workflow_set.try_to_move_stopping_workflows_to_stopped
        end

        def reset_expired_locks
          Connection.all_document_collections.each do |collection|
            Armagh::Document.force_reset_expired_locks( collection: collection )
          end
        end
      end
    end
  end
end
