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

require_relative 'action_instance'

module Armagh
  class ActionManager

    def initialize(caller, logger)
      @caller = caller
      @logger = logger
      @actions_by_name = {}
      @actions_by_doctype = {}
    end

    def set_available_action_instances(action_instances)
      old_actions_name = @actions_by_name

      @actions_by_name = {}
      @actions_by_doctype = {}

      if action_instances
        action_instances.each do |name, details|
          input_doctype = details['input_doctype']
          output_doctype = details['output_doctype']
          action_class_name = details['action_class_name']
          config = details['config']

          existing_action = old_actions_name[name]

          if existing_action && existing_action.action_class_name == action_class_name && existing_action.output_doctype == output_doctype && existing_action.input_doctype == input_doctype
            action = existing_action
          else
            begin
              action = ActionInstance.new(name, input_doctype, output_doctype, @caller, @logger, config, action_class_name)
            rescue NameError => e
              @logger.error "Action '#{name}' could not be created.  #{action_class_name} is an unknown class."
              @logger.debug "Available classes are #{self.class.available_actions}"
              action = nil
            end
          end

          if action
            @actions_by_name[name] = action
            @actions_by_doctype[input_doctype] ||= []
            @actions_by_doctype[input_doctype] << action
          end
        end
      end
    end

    def get_action_instance_names(input_doctype)
      actions = @actions_by_doctype[input_doctype]
      if actions
        actions.collect{|a| a.name}
      else
        @logger.warn "No actions defined for doctype '#{input_doctype}'"
        []
      end
    end

    def get_action_from_name(instance_name)
      action = @actions_by_name[instance_name]
      @logger.error "Unknown action '#{instance_name}'.  Available actions are #{@actions_by_name.keys}." unless action
      action
    end

    def self.available_actions
      actions = []
      actions.concat ClientActions.available_actions if defined? ClientActions
      actions.concat NoraghActions.available_actions if defined? NoraghActions
      actions
    end
  end
end
