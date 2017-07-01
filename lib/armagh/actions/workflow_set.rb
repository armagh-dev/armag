#
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
#
require 'configh'
require_relative 'workflow'

module Armagh
  module Actions

    class WorkflowConfigError < StandardError; end
    class ActionInstantiationError < StandardError; end
    class TriggerCollectError < StandardError; end
    class RefreshError < StandardError; end

    class WorkflowSet
      include Configh::Configurable
      attr_reader :action_config_named, :action_configs_handling_docspec, :collect_action_configs, :last_timestamp

      def self.for_admin(config_store)
        new(config_store, :admin)
      end

      def self.for_agent(config_store)
        new(config_store, :agent)
      end

      private_class_method :new

      def initialize(config_store, target)
        @config_store = config_store
        @target = target
        @workflows = {}
        @action_config_named = {}
        @action_configs_handling_docspec = {}
        @collect_action_configs = []
        @last_timestamp = nil
        refresh
      end

      def refresh(exclude_retired: true)
        case @target
          when :admin then
            reload_active_valid(exclude_retired: exclude_retired, force: true)
          when :agent then
            reload_active_valid
          else
            raise RefreshError, "refresh called with invalid target: #{@target}"
        end
      end

      def reload_all(exclude_retired: true)
        @workflows.clear
        @workflows = Workflow.find_all(@config_store, notify_to_refresh: self )
        @workflows.delete_if{ |wf| exclude_retired && wf.retired }
        @workflows = Hash[ @workflows.collect{ |wf|[  wf.name, wf ]}]
        true
      end

      def reload_active_valid(exclude_retired: true, force: false)
        last_timestamp = Action.max_timestamp(@config_store)
        if @last_timestamp != last_timestamp || force
          @action_config_named.clear
          @action_configs_handling_docspec.clear
          @collect_action_configs.clear

          reload_all(exclude_retired: exclude_retired)
          @workflows.values.select( &:valid? ).each do |wf|
            wf.valid_action_configs.each do |action_config|
              if action_config.action.active
                @action_config_named[ action_config.action.name ] = action_config
                @action_configs_handling_docspec[ action_config.input.docspec ] ||= []
                @action_configs_handling_docspec[ action_config.input.docspec ] << action_config
                @collect_action_configs << action_config if action_config.__type < Actions::Collect
              end
            end
           end
          @last_timestamp = last_timestamp
          return true
        end
        false
      end

      def list_workflows
        @workflows.values.collect(&:status)
      end

      def create_workflow(config_values)
        workflow_name = config_values.dig('workflow','name')
        @workflows[workflow_name] = Workflow.create(@config_store,workflow_name, notify_to_refresh: self )
      rescue Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      def get_workflow(workflow_name)
        @workflows[workflow_name]
      end

      def instantiate_action_from_config(action_config, caller, logger, state_collection)
        raise( ActionInstantiationError, 'Attempt to instantiate nil action config' ) unless action_config
        raise( ActionInstantiationError, 'Action not active' ) unless action_config.action.active
        action_type = action_config.__type
        action_type.new( caller, logger.name, action_config, state_collection )
      end

      def instantiate_action_named(action_name, caller, logger, state_collection)
        raise( ActionInstantiationError, 'Action name cannot be nil' ) unless action_name
        action_config = @action_config_named[ action_name ]
        raise( ActionInstantiationError, "Action #{action_name} not defined") unless action_config
        instantiate_action_from_config( action_config, caller, logger, state_collection )
      end

      def instantiate_actions_handling_docspec(docspec, caller, logger, state_collection)
        raise( ActionInstantiationError, 'Docspec cannot be nil' ) unless docspec
        action_configs = @action_configs_handling_docspec[ docspec ]
        actions = []

        if action_configs
          action_configs.each do |action_config|
            actions << instantiate_action_from_config( action_config, caller, logger, state_collection )
          end
        end

        actions
      end

      def actions_names_handling_docspec( docspec )
        raise( ActionInstantiationError, 'Docspec cannot be nil' ) unless docspec
        action_configs = @action_configs_handling_docspec[ docspec ] || []
        action_configs.collect{ |ac| ac.__name }
      end

      def trigger_collect(action_name)
        raise TriggerCollectError.new('No action name supplied.') if action_name.nil? || action_name.empty?
        action_config = @action_config_named[action_name]

        raise TriggerCollectError.new("Action #{action_name} is not an active action.") if action_config.nil?
        raise TriggerCollectError.new("Action #{action_name} is not a collect action.") unless action_config.__type < Armagh::Actions::Collect

        trigger = Utils::CollectionTrigger.new(self)
        trigger.trigger_individual_collection(action_config)
        true
      end
    end
  end
end
