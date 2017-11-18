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
require_relative 'base_document/document'
require_relative 'base_document/locking_crud'

require 'armagh/documents'
require_relative 'document'

module Armagh
  class ActionStateDocument < BaseDocument::Document
    include BaseDocument::LockingCRUD

    class ContentError < StandardError; end

    delegated_attr_accessor :action_name
    delegated_attr_accessor :content, validates_with: :is_a_hash

    def is_a_hash( value )
      value ||= {}
      raise ContentError, "State content must be a Hash object" unless value.is_a?( Hash )
      value
    end

    def self.default_collection
      Connection.action_state
    end

    def self.default_lock_wait_duration
      60
    end

    def self.default_lock_hold_duration
      120
    end

    def self.find_or_create_one_by_action_name_locked( action_name, caller, **locking_args )
      find_or_create_one_locked( { 'action_name' => action_name} , {'action_name' => action_name}, caller, **locking_args )
    end
  end
end
