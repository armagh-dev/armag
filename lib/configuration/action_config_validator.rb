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

module Armagh
  module Configuration
    module ActionConfigValidator
      def self.validate(action_config)
        # TODO ActionConfigValidator.validate Implement action config validation here
        errors = []
        warnings = []

        # Things to validate:
        # * No action of a given class
        # * Missing action fields (like docspecs)
        # * Call Action validation (probably need to clean up that error reporting)
        # * A given type/state pair can only be used for a single Parser, Publisher, or Collector
        # * A collector can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A parser can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A subscriber can only take a published document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document does not get changed
        # * A publisher only takes a document type (no state -- ready -> published is implied). it's only job is to publish that document.
        # * Check for loops

        {'valid' => errors.empty?, 'errors' => errors, 'warnings' => warnings}
      end


=begin # TODO ActionConfigValidator: integrate validate code pulled from action manager. CODE BELOW WAS REMOVED FROM ACTION MANAGER.  NEEDS TO BE CALLED FROM VALIDATE.
      private def validate
        errors = {}

        action_validation = validate_actions
        errors['action_validation'] = action_validation if action_validation

        docspec_mapping = validate_actions_docspec_mapping
        errors['docspec_mapping'] = docspec_mapping if docspec_mapping

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
            # TODO Fix split logging in action_config_validator pulled validate_actions
            @logger.error e
          end

          return errors unless instance

          unless instance.valid?
            errors ||= {}
            errors[action_name] = instance.validation_errors
          end

          if instance.is_a?(CollectAction)
            action_details['output_docspecs'].each do |docspec_name, _docspec|
              begin
                splitter = get_splitter(action_name, docspec_name)
              rescue => e
                errors ||= {}
                errors[action_name] ||= {}
                errors[action_name]['output_docspecs'] ||= {}
                errors[action_name]['output_docspecs'][docspec_name] ||= {}
                errors[action_name]['output_docspecs'][docspec_name]['_splitter'] ||= {}
                errors[action_name]['output_docspecs'][docspec_name]['_splitter']['initialize'] = e.message

                @logger.error 'Could not instantiate splitter'
            # TODO Fix split logging in action_config_validator pulled validate_actions
                @logger.error e
              end

              break unless splitter

              unless splitter.valid?
                errors ||= {}
                errors[action_name] ||= {}
                errors[action_name]['output_docspecs'] ||= {}
                errors[action_name]['output_docspecs'][docspec_name] ||= {}
                errors[action_name]['output_docspecs'][docspec_name]['_splitter'] ||= {}
                errors[action_name]['output_docspecs'][docspec_name]['_splitter'] = splitter.validation_errors
              end
            end
          end
        end

        errors
      end

      private def validate_actions_docspec_mapping
        publish_parse_actions = {}
        errors = nil
        @actions_by_docspec.each do |docspec, actions|
          docspec_s = docspec.to_s

          actions.each do |action|
            if action['class'].is_a?(PublishAction) || action['class'].is_a?(ParseAction)
              publish_parse_actions[docspec_s] ||= []
              publish_parse_actions[docspec_s] << action['name']
            end
          end

          if publish_parse_actions[docspec_s] && publish_parse_actions[docspec_s].length > 1
            errors ||= []
            errors << "#{docspec_s}: #{publish_parse_actions[docspec_s]}"
          end
        end
        errors
      end

      private def log_validation_errors(errors)
        error_msg = "Configuration validation failed with the following errors:\n"
        error_msg << generate_action_validation_msg(errors['action_validation']) if errors['action_validation']
        @logger.error error_msg
      end

      # TODO action_config_validator pulled generate_action_validation_msg: This should be cleaned up or may not be needed
      private; def generate_action_validation_msg(action_validation)
        msg = ''

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

          if validation['all_docspecs']
            msg << "  General DocSpec Errors:\n"
            validation['all_docspecs'].each do |message|
              msg << "    #{message}\n"
            end
          end

          if validation['input_docspecs']
            msg << "  Input DocSpec Errors:\n"
            validation['input_docspecs'].each do |name, message|
              msg << "    #{name}: #{message}\n"
            end
          end

          if validation['output_docspecs']
            msg << "  Output DocSpec Errors:\n"
            validation['output_docspecs'].each do |name, message|

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

      from main parser:
        unless ActionManager.defined_actions.include? action_class_name
          @logger.error "Agent Configuration is invalid - No action class '#{action_class_name}' exists.  Available actions are #{defined_actions}.  Abandoning action configuration."
          reset_actions
          break
        end
=end

    end
  end
end
