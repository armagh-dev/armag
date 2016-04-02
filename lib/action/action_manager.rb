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
      @splitter_by_action_docspec = {}
    end

    def set_available_actions(action_config)
      reset_actions

      action_config.each do |action_name, action_details|
        action_class_name = action_details['action_class_name']
        parameters = action_details['parameters'] || {}

        clazz = Object::const_get(action_class_name)

        if clazz < PublishAction
          input_doc_type = action_details['doc_type']
          output_docspecs = {'' => DocSpec.new(action_details['doc_type'], DocState::PUBLISHED)}
        else
          input_doc_type = action_details['input_doc_type']
          raw_output_docspecs = action_details['output_docspecs']
          output_docspecs = self.class.map_docspec_states(raw_output_docspecs)
          map_splitters(action_name, raw_output_docspecs) if clazz < CollectAction
        end

        input_state = clazz.is_a?(ConsumeAction) ? DocState::PUBLISHED : DocState::READY
        input_docspec = DocSpec.new(input_doc_type, input_state)

        action_settings = {'name' => action_name, 'input_docspec' => input_docspec, 'output_docspecs' => output_docspecs,
                           'parameters' => parameters, 'class_name' => action_class_name, 'class' => clazz}

        @actions_by_name[action_name] = action_settings

        @actions_by_docspec[input_docspec] ||= []
        @actions_by_docspec[input_docspec] << action_settings
      end
    rescue => e
      Logging.error_exception(@logger, e, 'Invalid agent configuration.  Could not configure actions.')
      reset_actions
    end

    def get_action(name)
      action_details = @actions_by_name[name]
      if action_details
        instantiate_action(action_details)
      else
        @logger.error "Unknown action '#{name}'.  Available actions are #{@actions_by_name.keys}."
        nil
      end
    end

    def get_action_names_for_docspec(input_docspec)
      actions = @actions_by_docspec[input_docspec]
      if actions
        actions.collect { |a| a['name'] }
      else
        @logger.warn "No actions defined for docspec '#{input_docspec}'"
        []
      end
    end

    def get_splitter(action_name, output_docspec_name)
      output_docspec = @actions_by_name[action_name]['output_docspecs'][output_docspec_name] if @actions_by_name[action_name] && @actions_by_name[action_name]['output_docspecs']
      if @splitter_by_action_docspec[action_name] && @splitter_by_action_docspec[action_name][output_docspec_name] && output_docspec
        instantiate_splitter(@splitter_by_action_docspec[action_name][output_docspec_name], output_docspec)
      else
        nil
      end
    end

    def self.map_docspec_states(docspecs)
      converted_docspecs = {}

      docspecs.each do |name, details|
        converted_docspecs[name] = DocSpec.new(details['type'], details['state'])
      end
      converted_docspecs
    end

    def self.defined_actions
      actions = []
      actions.concat CustomActions.defined_actions if defined? CustomActions
      actions.concat StandardActions.defined_actions if defined? StandardActions
      actions
    end

    private def map_splitters(action_name, output_docspecs)
      output_docspecs.each do |docspec_name, output_docspec|
        splitter_details = output_docspec['splitter']
        if splitter_details
          splitter_class_name = splitter_details['splitter_class_name']
          splitter_parameters = splitter_details['parameters'] || {}
          splitter_settings = {'parameters' => splitter_parameters, 'class_name' => splitter_class_name, 'class' => Object::const_get(splitter_class_name)}
          @splitter_by_action_docspec[action_name] ||= {}
          @splitter_by_action_docspec[action_name][docspec_name] = splitter_settings
        end
      end
    end

    private def reset_actions
      @actions_by_name.clear
      @actions_by_docspec.clear
      @splitter_by_action_docspec.clear
    end

    private def instantiate_action(action_details)
      action_details['class'].new(action_details['name'], @caller, @logger, action_details['parameters'], action_details['output_docspecs'])
    end

    private def instantiate_splitter(splitter_details, docspec)
      splitter_details['class'].new(@caller, @logger, splitter_details['parameters'], docspec)
    end
  end
end
