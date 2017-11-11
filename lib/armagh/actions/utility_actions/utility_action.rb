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

require 'armagh/support/cron'
require 'armagh/actions'

module Armagh
  module Actions

    class ConfigurationError < StandardError
    end

    class UtilityAction < Action
      include Configh::Configurable

      define_parameter name: 'schedule', type: 'populated_string', required: false, description: 'Schedule to run the utility.  Cron syntax.  If not set, Utility must be manually triggered.', prompt: '*/15 * * * *', group: 'utility'
      define_group_validation_callback callback_class: UtilityAction, callback_method: :report_validation_errors

      UTILITY_DOCTYPE_PREFIX = '__UTILITY__'
      VALID_INPUT_STATE = Armagh::Documents::DocState::READY

      def self.valid_action_superclasses
        super << "Armagh::Actions::UtilityAction"
      end

      def self.simple_name
        name[/([^\:]+)$/, 1].downcase
      end

      def self.default_config_values
        {
            'action' => { 'name' => simple_name, 'active' => true },
            'utility' => { 'schedule' => default_cron  }
        }
      end

      def self.add_action_params( name, values )
        new_values = super
        new_values[ 'input' ] ||= {}
        new_values['input']['docspec'] = "#{UTILITY_DOCTYPE_PREFIX}#{new_values['action']['name']}:#{Documents::DocState::READY}"

        new_values
      end

      def self.default_cron
        '0 3 * * *'
      end

      def self.find_or_create_all_configurations( config_store )

        configs = []
        Armagh::Actions::UtilityAction.defined_utilities.each do |utility_class|
          configs << utility_class.find_or_create_configuration( config_store, utility_class.simple_name, values_for_create: utility_class.default_config_values, maintain_history: true )
        end
        configs
      end

      def self.inherited(base)
        base.register_action
        base.define_default_input_type "#{UTILITY_DOCTYPE_PREFIX}#{base.simple_name}"

        base.define_singleton_method(:define_default_input_type) { |*args|
          raise ConfigurationError, 'You cannot define default input types for utilities'
        }
      end

      def UtilityAction.report_validation_errors( candidate_config )
        errors = nil
        schedule = candidate_config.utility.schedule
        errors = "Schedule '#{schedule}' is not valid cron syntax." if schedule && !Support::Cron.valid_cron?(schedule)
        errors
      end

      def run
        raise Errors::ActionMethodNotImplemented.new 'Utility actions must overwrite the run method.'
      end

      def self.defined_utilities
        utils = Armagh::Actions::UtilityActions.constants.collect do |c|
          maybe_class = Armagh::Actions::UtilityActions.const_get(c)
          maybe_class if maybe_class.is_a?(Class) && maybe_class < Armagh::Actions::UtilityAction
        end
        utils.compact
      end
    end
  end
end
