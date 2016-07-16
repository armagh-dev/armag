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

require 'armagh/actions'
require 'armagh/documents/doc_spec'

require_relative '../configuration/action_config_validator'
require_relative '../errors'
require_relative '../logging'

module Armagh
  class ActionManager

    def initialize(caller_instance, logger)
      @caller = caller_instance
      @logger = logger
      @actions_by_name = {}
      @actions_by_docspec = {}
      @divider_by_action_docspec = {}
    end

    def set_available_actions(action_config)
      reset_actions

      action_config.each do |action_name, action_details|
        action_class_name = action_details['action_class_name']
        parameters = action_details['parameters'] || {}

        clazz = Object::const_get(action_class_name)

        if clazz < Actions::Publish
          input_doc_type = action_details['doc_type']
          output_docspecs = {'' => Documents::DocSpec.new(action_details['doc_type'], Documents::DocState::PUBLISHED)}
        else
          input_doc_type = action_details['input_doc_type']
          raw_output_docspecs = action_details['output_docspecs']
          output_docspecs = self.class.map_docspec_states(raw_output_docspecs)
          map_dividers(action_name, raw_output_docspecs) if clazz < Actions::Collect
        end

        input_state = clazz < Actions::Consume ? Documents::DocState::PUBLISHED : Documents::DocState::READY
        input_docspec = Documents::DocSpec.new(input_doc_type, input_state)

        action_settings = {'name' => action_name, 'input_docspec' => input_docspec, 'output_docspecs' => output_docspecs,
                           'parameters' => parameters, 'class_name' => action_class_name, 'class' => clazz}

        @actions_by_name[action_name] = action_settings

        @actions_by_docspec[input_docspec] ||= []
        @actions_by_docspec[input_docspec] << action_settings
      end
    rescue => e
      Logging.ops_error_exception(@logger, e, 'Invalid agent configuration.  Could not configure actions.')
      reset_actions
    end

    def get_action(name)
      action_details = @actions_by_name[name]
      if action_details
        instantiate_action(action_details)
      else
        @logger.ops_error "Unknown action '#{name}'.  Available actions are #{@actions_by_name.keys}."
        nil
      end
    end

    def get_action_names_for_docspec(input_docspec)
      actions = @actions_by_docspec[input_docspec]
      if actions
        actions.collect { |a| a['name'] }
      else
        @logger.ops_warn "No actions defined for docspec '#{input_docspec}'"
        []
      end
    end

    def get_divider(action_name, output_docspec_name)
      output_docspec = @actions_by_name[action_name]['output_docspecs'][output_docspec_name] if @actions_by_name[action_name] && @actions_by_name[action_name]['output_docspecs']
      if @divider_by_action_docspec[action_name] && @divider_by_action_docspec[action_name][output_docspec_name] && output_docspec
        instantiate_divider(action_name, @divider_by_action_docspec[action_name][output_docspec_name], output_docspec)
      else
        nil
      end
    end

    def self.map_docspec_states(docspecs)
      converted_docspecs = {}

      docspecs.each do |name, details|
        converted_docspecs[name] = Documents::DocSpec.new(details['type'], details['state'])
      end
      converted_docspecs
    end

    def self.defined_actions
      actions = []
      actions.concat CustomActions.defined_actions if defined? CustomActions
      actions.concat StandardActions.defined_actions if defined? StandardActions
      actions
    end

    private def map_dividers(action_name, output_docspecs)
      output_docspecs.each do |docspec_name, output_docspec|
        divider_details = output_docspec['divider']
        if divider_details
          divider_class_name = divider_details['divider_class_name']
          divider_parameters = divider_details['parameters'] || {}
          divider_settings = {'parameters' => divider_parameters, 'class_name' => divider_class_name, 'class' => Object::const_get(divider_class_name)}
          @divider_by_action_docspec[action_name] ||= {}
          @divider_by_action_docspec[action_name][docspec_name] = divider_settings
        end
      end
    end

    private def reset_actions
      @actions_by_name.clear
      @actions_by_docspec.clear
      @divider_by_action_docspec.clear
    end

    private def instantiate_action(action_details)
      logger_name = "Armagh::Application::Action::#{@caller.uuid}/Action-#{action_details['name']}"
      action_details['class'].new(action_details['name'], @caller, logger_name, action_details['parameters'], action_details['output_docspecs'])
    end

    private def instantiate_divider(action_name, divider_details, docspec)
      divider_name = "Divider-#{action_name}"
      logger_name = "Armagh::Application::Divider::#{@caller.uuid}/#{divider_name}"
      divider_details['class'].new(divider_name, @caller, logger_name, divider_details['parameters'], docspec)
    end
  end
end
