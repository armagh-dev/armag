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

require 'armagh/documents/doc_type_state'

require_relative '../errors'

module Armagh
  class ActionManager

    # TODO - More comprehensive validation

    def initialize(caller, logger)
      @caller = caller
      @logger = logger
      @actions_by_name = {}
      @actions_by_doctype = {}
      @splitter_by_action_doctype = {}
    end

    def set_available_actions(action_config)
      reset_actions

      defined_actions = ActionManager.defined_actions

      action_config.each do |action_name, action_details|
        action_class_name = action_details['action_class_name']
        parameters = action_details['parameters']

        unless defined_actions.include? action_class_name
          @logger.error "Agent Configuration is invalid - No action class '#{action_class_name}' exists.  Available actions are #{defined_actions}.  Abandoning action configuration."
          reset_actions
          break
        end

        klass = Object::const_get(action_class_name)

        if klass < PublishAction
          doctype = action_details['doctype']
          input_doctypes = {'' => DocTypeState.new(doctype, DocState::READY)}
          output_doctypes = {'' => DocTypeState.new(doctype, DocState::PUBLISHED)}
        else
          raw_input_doctypes = action_details['input_doctypes']
          raw_output_doctypes = action_details['output_doctypes']

          input_doctypes = map_doctype_states(raw_input_doctypes)
          output_doctypes = map_doctype_states(raw_output_doctypes)

          map_splitters(action_name, raw_output_doctypes) if klass < CollectAction
        end

        action_settings = {'name' => action_name, 'input_doctypes' => input_doctypes, 'output_doctypes' => output_doctypes,
                           'parameters' => parameters, 'class_name' => action_class_name, 'class' => klass}

        @actions_by_name[action_name] = action_settings

        input_doctypes.each do |_name, input_doctype|
          @actions_by_doctype[input_doctype] ||= []
          @actions_by_doctype[input_doctype] << action_settings
        end
      end

      validate
    rescue => e
      @logger.error 'Invalid agent configuration.  Could not parse actions.'
      @logger.error e
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

    def get_action_names_for_doctype(input_doctype)
      actions = @actions_by_doctype[input_doctype]
      if actions
        actions.collect { |a| a['name'] }
      else
        @logger.warn "No actions defined for doctype '#{input_doctype}'"
        []
      end
    end

    def get_splitter(action_name, output_doctype_name)
      output_doctype = @actions_by_name[action_name]['output_doctypes'][output_doctype_name]
      if @splitter_by_action_doctype[action_name] && @splitter_by_action_doctype[action_name][output_doctype_name] && output_doctype
        instantiate_splitter(@splitter_by_action_doctype[action_name][output_doctype_name], output_doctype)
      else
        nil
      end
    end

    def self.defined_actions
      actions = []
      actions.concat CustomActions.defined_actions if defined? CustomActions
      actions.concat StandardActions.defined_actions if defined? StandardActions
      actions
    end

    private def map_doctype_states(doctypes)
      converted_doctypes = {}

      doctypes.each do |name, details|
        converted_doctypes[name] = DocTypeState.new(details['type'], details['state'])
      end
      converted_doctypes
    end

    private def map_splitters(action_name, output_doctypes)
      output_doctypes.each do |doctype_name, output_doctype|
        splitter_details = output_doctype['splitter']
        if splitter_details
          splitter_class_name = splitter_details['splitter_class_name']
          splitter_parameters = splitter_details['parameters']
          splitter_settings = {'parameters' => splitter_parameters, 'class_name' => splitter_class_name, 'class' => Object::const_get(splitter_class_name)}
          @splitter_by_action_doctype[action_name] ||= {}
          @splitter_by_action_doctype[action_name][doctype_name] = splitter_settings
        end
      end
    end

    # TODO Move validation into the config managers.  Validate config as a whole.
    private def validate
      errors = {}

      action_validation = validate_actions
      errors['action_validation'] = action_validation if action_validation

      doctype_mapping = validate_actions_doctype_mapping
      errors['doctype_mapping'] = doctype_mapping if doctype_mapping

      if errors.any?
        log_validation_errors(errors)
        reset_actions
      end
    end

    private def validate_actions
      errors = nil
      @actions_by_name.each do |action_name, action_details|
        begin
          instance = instantiate_action(action_details)
        rescue => e
          errors ||= {}
          errors[action_name] ||= {}
          errors[action_name]['instantiation'] = e.message

          @logger.error 'Could not instantiate action'
          # TODO Split Logging
          @logger.error e
        end

        return errors unless instance

        unless instance.valid?
          errors ||= {}
          errors[action_name] = instance.validation_errors
        end

        if instance.is_a?(CollectAction)
          action_details['output_doctypes'].each do |doctype_name, _doctype|
            begin
              splitter = get_splitter(action_name, doctype_name)
            rescue => e
              errors ||= {}
              errors[action_name] ||= {}
              errors[action_name]['output_doctypes'] ||= {}
              errors[action_name]['output_doctypes'][doctype_name] ||= {}
              errors[action_name]['output_doctypes'][doctype_name]['_splitter'] ||= {}
              errors[action_name]['output_doctypes'][doctype_name]['_splitter']['initialize'] = e.message

              @logger.error 'Could not instantiate splitter'
              # TODO Split Logging
              @logger.error e
            end

            break unless splitter

            unless splitter.valid?
              errors ||= {}
              errors[action_name] ||= {}
              errors[action_name]['output_doctypes'] ||= {}
              errors[action_name]['output_doctypes'][doctype_name] ||= {}
              errors[action_name]['output_doctypes'][doctype_name]['_splitter'] ||= {}
              errors[action_name]['output_doctypes'][doctype_name]['_splitter'] = splitter.validation_errors
            end
          end
        end
      end

      errors
    end

    private def validate_actions_doctype_mapping
      publish_parse_actions = {}
      errors = nil
      @actions_by_doctype.each do |doctype, actions|
        doctype_s = doctype.to_s

        actions.each do |action|
          if action['class'].is_a?(PublishAction) || action['class'].is_a?(ParseAction)
            publish_parse_actions[doctype_s] ||= []
            publish_parse_actions[doctype_s] << action['name']
          end
        end

        if publish_parse_actions[doctype_s] && publish_parse_actions[doctype_s].length > 1
          errors ||= []
          errors << "#{doctype_s}: #{publish_parse_actions[doctype_s]}"
        end
      end
      errors
    end

    private def log_validation_errors(errors)
      error_msg = "Configuration validation failed with the following errors:\n"
      error_msg << generate_action_validation_msg(errors['action_validation']) if errors['action_validation']
      @logger.error error_msg
    end

    # TODO This should be cleaned up
    private; def generate_action_validation_msg(action_validation)
      msg = ''

      puts action_validation
      action_validation.each do |name, validation|
        msg << "Errors for action '#{name}':\n"

        if validation['instantiation']
          msg << "  Instantiation Error:\n"
          msg << "    #{validation['instantiation']}\n"
        end

        if validation['parameters']
          msg << "  Parameter Errors:\n"
          validation['parameters'].each do |name, message|
            msg << "    #{name}: #{message}\n"
          end
        end

        if validation['general']
          msg << "  General Action Errors:\n"
          validation['general'].each do |message|
            msg << "    #{message}\n"
          end
        end

        if validation['all_doctypes']
          msg << "  General Doctype Errors:\n"
          validation['all_doctypes'].each do |message|
            msg << "    #{message}\n"
          end
        end

        if validation['input_doctypes']
          msg << "  Input Doctype Errors:\n"
          validation['input_doctypes'].each do |name, message|
            msg << "    #{name}: #{message}\n"
          end
        end

        if validation['output_doctypes']
          msg << "  Output Doctype Errors:\n"
          validation['output_doctypes'].each do |name, message|

            if message.is_a?(Hash) && message['_splitter']
              splitter_validation = message['_splitter']

              msg << "    Splitter Errors:\n"

              if splitter_validation['instantiation']
                msg << "      Instantiation Error:\n"
                msg << "        #{splitter_validation['instantiation']}\n"
              end

              if splitter_validation['parameters']
                msg << "      Parameter Errors:\n"
                splitter_validation['parameters'].each do |name, message|
                  msg << "      #{name}: #{message}\n"
                end
              end

              if splitter_validation['general']
                msg << "      General Splitter Errors:\n"
                splitter_validation['general'].each do |message|
                  msg << "      #{message}\n"
                end
              end
            else
              msg << "    #{name}: #{message}\n"
            end
          end
        end
      end

      msg << 'Abandoning agent configuration.'

      msg
    end

    private def reset_actions
      @actions_by_name.clear
      @actions_by_doctype.clear
      @splitter_by_action_doctype.clear
    end

    private def instantiate_action(action_details)
      # TODO Handle publish w/ only one doctype
      # TODO There's a chance subscribers won't produce a document, either [it appears as though this behaves correctly as is]
      action_details['class'].new(action_details['name'], @caller, @logger, action_details['parameters'], action_details['input_doctypes'], action_details['output_doctypes'])
    end

    private def instantiate_splitter(splitter_details, doctype)
      splitter_details['class'].new(@caller, @logger, splitter_details['parameters'], doctype)
    end
  end
end
