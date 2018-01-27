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
require 'armagh/support/random'

require_relative 'base_document/document'
require_relative 'base_document/locking_crud'

module Armagh
  class TriggerManagerSemaphoreDocument < BaseDocument::Document
    include BaseDocument::LockingCRUD

    NAME = 'trigger_manager_document'

    delegated_attr_accessor :name
    delegated_attr_accessor :last_run
    delegated_attr_accessor :seen_actions

    def self.default_collection
      Connection.semaphores
    end

    def self.default_lock_hold_duration
      90
    end

    def self.default_lock_wait_duration
      1
    end

    def self.ensure_one_exists
      begin
        create_one_unlocked( {'name' => NAME, 'last_run' => {}, 'seen_actions' => [] })
      rescue Armagh::Connection::DocumentUniquenessError => e
        # ignore uniqueness error
      end
    end
  end
end
