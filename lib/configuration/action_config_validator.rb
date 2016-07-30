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

require 'tsort'

require 'armagh/actions'

require_relative '../action/action_manager'
require_relative '../utils/t_sortable_hash'

module Armagh
  module Configuration
    class ActionConfigValidator

      ACTION_FIELDS = {
          'action_class_name' => String,
          'parameters' => Hash
          #doc types and specs are handled separately since they depend on the action type
      }

      DOCSPEC_FIELDS = {
          'type' => String,
          'state' => String
          #divider is handled separately since it depends on the action type
      }

      DIVIDER_FIELDS = {
          'divider_class_name' => String,
          'parameters' => Hash
      }

      VALID_OUTPUT_DOC_STATES = [Documents::DocState::READY, Documents::DocState::WORKING]

      def initialize
        @errors = []
        @warnings = []

        @input_docspecs = {}
        @output_docspecs = {}
        @action_outputs = {}

        @docspec_flow = Utils::TsortableHash.new
      end

      def error?
        @errors.any?
      end

      def validate(action_config)
        @errors.clear
        @warnings.clear

        @input_docspecs.clear
        @output_docspecs.clear
        @action_outputs.clear
        @docspec_flow.clear

        if action_config.empty?
          @warnings << 'Action Configuration is empty.'
        else
          field_validation(action_config)
          workflow_validation unless error?
        end

        {'valid' => !error?, 'errors' => @errors.uniq, 'warnings' => @warnings.uniq}
      end

      private def field_validation(action_config)
        action_config.each do |action_name, action_settings|
          if action_settings.is_a?(Hash)
            validate_action_name(action_name)
            validate_action_settings(action_name, action_settings)
          else
            @errors << "Action '#{action_name}' needs to be a Hash.  Was a #{action_settings.class}."
          end
        end
      end

      private def validate_action_name(action_name)
        @errors << 'An action was found without a name' if blank? action_name
      end

      private def validate_action_settings(action_name, action_settings)
        validate_action_fields(action_name, action_settings)
        return if error?

        output_docspecs = action_settings['output_docspecs']

        begin
          clazz = Object.const_get(action_settings['action_class_name'])
          case
            when clazz < Actions::Collect
              validate_collect(action_name, action_settings)
            when clazz < Actions::Split
              validate_split(action_name, action_settings)
            when clazz < Actions::Publish
              validate_publish(action_name, action_settings)
              output_docspecs = {'' => {'type' => action_settings['doc_type'], 'state' => Documents::DocState::PUBLISHED}}
            when clazz < Actions::Consume
              validate_consume(action_name, action_settings)
            else
              @errors << "Class '#{action_settings['action_class_name']}' from action '#{action_name}' is not a CollectAction, SplitAction, PublishAction, or ConsumeAction."
              return # We can't do additional checking if we don't know what action type we have
          end

          unless error?
            validate_action_instance(action_name, clazz, action_settings['parameters'], output_docspecs)
          end
        rescue NameError
          @errors << "Class '#{action_settings['action_class_name']}' from action '#{action_name}' does not exist."
        end
      end

      private def validate_action_fields(action_name, action_settings)
        ACTION_FIELDS.each do |name, type|
          setting = action_settings[name]

          if setting.nil?
            @errors << "Action '#{action_name}' does not have '#{name}'."
          elsif !setting.is_a?(type)
            @errors << "Field '#{name}' from action '#{action_name}' must be a '#{type}'.  It is a '#{setting.class}'."
          end
        end

        unless action_settings['doc_type'] || (action_settings['input_doc_type'] && action_settings['output_docspecs'])
          @errors << "Action '#{action_name}' needs a 'doc_type' field if it is a PublishAction or an 'input_doc_type' and 'output_docspecs' field if it is any other action type."
        end

        unknown_fields = action_settings.keys - ACTION_FIELDS.keys - %w(doc_type input_doc_type output_docspecs)
        @warnings << "Action '#{action_name}' has the following unexpected fields: #{unknown_fields}." unless unknown_fields.empty?
      end

      private def validate_collect(action_name, action_settings)
        action_type = 'collect'
        input_doc_type = action_settings['input_doc_type']
        validate_input_doc_type(action_name, input_doc_type, action_type)
        validate_output_docspecs(action_name, input_doc_type, action_settings['output_docspecs'], action_type, true)
        insert_action_for_loop_check(input_doc_type, action_settings['output_docspecs'], action_type)
      end

      private def validate_split(action_name, action_settings)
        action_type = 'split'
        input_doc_type = action_settings['input_doc_type']
        validate_input_doc_type(action_name, input_doc_type, action_type)
        validate_output_docspecs(action_name, input_doc_type, action_settings['output_docspecs'], action_type)
        insert_action_for_loop_check(input_doc_type, action_settings['output_docspecs'], action_type)
      end

      private def validate_publish(action_name, action_settings)
        action_type = 'publish'
        doc_type = action_settings['doc_type']
        validate_doctype(action_name, doc_type, action_type)
        insert_action_for_loop_check(doc_type, doc_type, action_type)
      end

      private def validate_consume(action_name, action_settings)
        action_type = 'consume'
        input_doc_type = action_settings['input_doc_type']
        validate_input_doc_type(action_name, input_doc_type, action_type)
        validate_output_docspecs(action_name, input_doc_type, action_settings['output_docspecs'], action_type, false, true)
        insert_action_for_loop_check(input_doc_type, action_settings['output_docspecs'], action_type)
      end

      private def validate_action_instance(action_name, clazz, parameters, raw_output_docspecs)
        parameters ||= {}
        output_docspecs = ActionManager.map_docspec_states(raw_output_docspecs)
        mapped_parameters = ActionManager.map_parameters(clazz, parameters)
        instance = clazz.new(action_name, nil, nil, mapped_parameters, output_docspecs)
        class_validation = instance.validate
        class_validation['errors'].each { |err| @errors << "Action '#{action_name}' error: #{err}" }
        class_validation['warnings'].each { |warn| @warnings << "Action '#{action_name}' warning: #{warn}" }
      rescue => e
        @errors << "Action '#{action_name}' validation failed: #{e}"
      end

      private def validate_input_doc_type(action_name, input_doc_type, action_type)
        begin
          input_docspec = create_input_docspec(input_doc_type, action_type)

          @input_docspecs[input_docspec] ||= []
          @input_docspecs[input_docspec] << {'action_name' => action_name, 'action_type' => action_type}
        rescue Documents::Errors::DocSpecError => e
          @errors << "Action '#{action_name}', 'input_doc_type' has an error: #{e.message}'"
        end
      end

      private def validate_output_docspecs(action_name, input_doc_type, output_docspecs, action_type, allow_divider = false, allow_empty = false)
        output_docspecs.each do |docspec_name, docspec_settings|
          validate_output_docspec_name(action_name, docspec_name)
          validate_output_docspec_fields(action_name, docspec_name, docspec_settings, allow_divider)

          if input_doc_type == docspec_settings['type']
            @errors << "Input doctype and output docspec '#{docspec_name}' from action '#{action_name}' are the same but they must be different."
          end

          next if error?

          begin
            output_docspec = Documents::DocSpec.new(docspec_settings['type'], docspec_settings['state'])
            @output_docspecs[output_docspec] ||= []
            @output_docspecs[output_docspec] << {'action_name' => action_name, 'action_type' => action_type, 'docspec_name' => docspec_name}
            @action_outputs[action_name] ||= []
            @action_outputs[action_name] << output_docspec
          rescue Documents::Errors::DocSpecError => e
            @errors << "Action '#{action_name}', docspec '#{docspec_name}' has an error: #{e.message}'"
          end
        end
      end

    private def validate_doctype(action_name, doc_type, action_type)
        if doc_type.is_a? String
          begin
            input_docspec = Documents::DocSpec.new(doc_type, Documents::DocState::READY)
            @input_docspecs[input_docspec] ||= []
            @input_docspecs[input_docspec] << {'action_name' => action_name, 'action_type' => action_type}

            output_docspec = Documents::DocSpec.new(doc_type, Documents::DocState::PUBLISHED)
            @output_docspecs[output_docspec] ||= []
            @output_docspecs[output_docspec] << {'action_name' => action_name, 'action_type' => action_type}
            @action_outputs[action_name] ||= []
            @action_outputs[action_name] << output_docspec
          rescue Documents::Errors::DocSpecError => e
            @errors << "Action '#{action_name}' 'doc_type' has an error: #{e.message}'"
          end
        else
          @errors << "Doc type '#{doc_type}' from '#{action_name}' must be a 'String'.  It is a '#{doc_type.class}'."
        end
      end

      private def validate_output_docspec_name(action_name, docspec_name)
        @errors << "Action '#{action_name}' had an output docspec without a name." if blank? docspec_name
      end

      private def validate_output_docspec_fields(action_name, docspec_name, docspec_settings, allow_divider = false)
        DOCSPEC_FIELDS.each do |name, type|
          setting = docspec_settings[name]

          if blank? setting
            @errors << "Action '#{action_name}', docspec '#{docspec_name}' does not have '#{name}'."
          elsif !setting.is_a?(type)
            @errors << "Field '#{name}' from action '#{action_name}', docspec '#{docspec_name}' must be a '#{type}'.  It is a '#{setting.class}'."
          end
        end

        unknown_fields = docspec_settings.keys - DOCSPEC_FIELDS.keys

        if allow_divider && docspec_settings['divider']
          unknown_fields -= ['divider']
          validate_output_docspec_divider(action_name, docspec_name, docspec_settings)
        end

        @warnings << "Action '#{action_name}', docspec '#{docspec_name}' has the following unexpected fields: #{unknown_fields}." unless unknown_fields.empty?
      end

      private def validate_output_docspec_divider(action_name, docspec_name, docspec_settings)
        divider_settings = docspec_settings['divider']

        unless divider_settings.is_a? Hash
          @errors << "Action '#{action_name}', docspec '#{docspec_name}' divider must be a 'Hash'.  It is a '#{divider_settings.class}'."
          return
        end

        DIVIDER_FIELDS.each do |name, type|
          setting = divider_settings[name]

          if setting.nil?
            @errors << "Action '#{action_name}', docspec '#{docspec_name}' divider does not have '#{name}'."
          elsif !setting.is_a?(type)
            @errors << "Field '#{name}' from action '#{action_name}', docspec '#{docspec_name}' divider must be a '#{type}'.  It is a '#{setting.class}'."
          end
        end

        unknown_fields = divider_settings.keys - DIVIDER_FIELDS.keys
        @warnings << "Action '#{action_name}', docspec '#{docspec_name}' divider has the following unexpected fields: #{unknown_fields}." unless unknown_fields.empty?

        unless error?
          clazz = Object.const_get(divider_settings['divider_class_name'])
          validate_divider_instance(action_name, clazz, divider_settings['parameters'], docspec_settings)
        end
      end

      private def validate_divider_instance(action_name, clazz, parameters, docspec_settings)
        output_docspec = Documents::DocSpec.new(docspec_settings['type'], docspec_settings['state'])
        mapped_parameters = ActionManager.map_parameters(clazz, parameters)
        instance = clazz.new("Divider-#{action_name}", nil, nil, mapped_parameters, output_docspec)
        divider_validation = instance.validate

        divider_validation['errors'].each { |err| @errors << "Action '#{action_name}' divider error: #{err}" }
        divider_validation['warnings'].each { |warn| @warnings << "Action '#{action_name}' divider warning: #{warn}" }
      rescue => e
        @errors << "Action '#{action_name}' divider validation failed: #{e}"
      end

      private def workflow_validation
        validate_workflow_inputs
        validate_workflow_used
        validate_workflow_loops
      end

      private def validate_workflow_inputs
        @input_docspecs.each do |docspec, actions|
          unless docspec.state == Documents::DocState::PUBLISHED
            action_names = actions.collect { |a| a['action_name'] }
            @errors << "Input docspec '#{docspec}' cannot be shared between multiple actions.  Shared by: #{action_names}" if action_names.length > 1
          end
        end
      end

      private def validate_workflow_used
        validate_unused_ready_specs
        validate_unused_working_specs
        validate_noncreated_inputs
      end

      private def validate_unused_ready_specs
        unused_docspecs = @output_docspecs.keys - @input_docspecs.keys

        unused_docspecs.each do |docspec|
          if docspec.state == Documents::DocState::READY
            action_names = @output_docspecs[docspec].collect { |a| a['action_name'] }
            @warnings << "Actions #{action_names} produce docspec '#{docspec}', but no action takes that docspec as input."
          end
        end
      end

      private def validate_unused_working_specs
        unfinished_working = []
        finished_working = []

        @action_outputs.each do |_action_name, specs|
          working_types = specs.collect { |s| s.type if s.state == Documents::DocState::WORKING }.compact
          ready_types = specs.collect { |s| s.type if s.state == Documents::DocState::READY }.compact

          unfinished_working.concat working_types - ready_types
          finished_working.concat working_types & ready_types
        end

        (unfinished_working-finished_working).each do |doc_type|
          @warnings << "No actions convert '#{doc_type}' from a working to a ready state."
        end
      end

      def validate_noncreated_inputs
        uncreated_docspecs = @input_docspecs.keys - @output_docspecs.keys

        uncreated_docspecs.each do |docspec|
          @input_docspecs[docspec].each do |action|
            @warnings << "Action #{action['action_name']} takes in docspec '#{docspec}', but no action creates that docspec." unless action['action_type'] == 'collect'
          end
        end
      end

      private def validate_workflow_loops
        begin
          @docspec_flow.tsort
        rescue TSort::Cyclic
          @errors << 'Action configuration has a cycle.'
        end
      end

      private def create_input_docspec(input_doc_type, action_type)
        case action_type
          when 'consume'
            Documents::DocSpec.new(input_doc_type, Documents::DocState::PUBLISHED)
          else
            Documents::DocSpec.new(input_doc_type, Documents::DocState::READY)
        end
      end

      private def insert_action_for_loop_check(input_doc_type, output_docspecs, action_type)
        return if error?
        input_docspec = create_input_docspec(input_doc_type, action_type)
        return if error?

        @docspec_flow[input_docspec] ||= []

        if output_docspecs.is_a? String
          @docspec_flow[input_docspec] << Documents::DocSpec.new(output_docspecs, Documents::DocState::PUBLISHED)
        else
          output_docspecs.each do |_name, spec|
            @docspec_flow[input_docspec] << Documents::DocSpec.new(spec['type'], spec['state'])
          end
        end
      end

      private def blank?(item)
        item.nil? || (item.respond_to?(:empty) && item.empty?)
      end
    end
  end
end
