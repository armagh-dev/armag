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

require 'armagh/documents'
require 'armagh/actions/collect'
require 'armagh/support/cron'

require_relative 'interruptible_sleep'
require_relative '../actions/workflow_set'
require_relative '../document/trigger_document'
require_relative '../logging'

module Armagh
  module Utils
    class CollectionTrigger
      attr_reader :logger

      def initialize(workflow_set)
        @workflow_set = workflow_set
        @running = false
        @last_run = {}
        @seen_actions = []
        @logger = Logging.set_logger('Armagh::Application::CollectionTrigger')
      end

      def start
        @thread ||= Thread.new { run }
        @thread.abort_on_exception = true
      end

      def stop
        Thread.new {@logger.debug 'Stopping Collection Trigger'}.join
        @running = false
        @thread.join if @thread
        @thread = nil
      end

      def running?
        @running && @thread.alive?
      end

      def trigger_individual_collection(config)
        @logger.debug "Triggering #{config.action.name} collection"
        docspec = config.input.docspec
        pending_actions = @workflow_set.actions_names_handling_docspec(docspec)
        TriggerDocument.ensure_one_exists(state: docspec.state, type: docspec.type, pending_actions: pending_actions)
      rescue => e
        Logging.ops_error_exception(@logger, e, 'Document insertion failed.')
      end

      private def run
        @logger.debug 'Starting collection trigger.'
        @running = true
        while @running
          begin
            trigger_actions
            remove_unseen_actions
          rescue => e
            Logging.dev_error_exception(@logger, e, 'Collection trigger failed.')
          end
          InterruptibleSleep.interruptible_sleep(1) { !@running }
        end

        Thread.new {@logger.info 'Collection Trigger Stopped'}.join
      end

      private def trigger_actions
        @workflow_set.collect_action_configs.each do |config|
          next unless config.action.active

          now = Time.now
          name = config.action.name
          @seen_actions << name
          schedule = config.collect.schedule

          next unless schedule

          @last_run[name] ||= now
          next_run = Armagh::Support::Cron.next_execution_time(schedule, @last_run[name])
          if now >= next_run
            trigger_individual_collection(config)
            @last_run[name] = now
            @logger.debug("Collection #{name} scheduled to run at #{Armagh::Support::Cron.next_execution_time(schedule, now)}.")
          elsif now == @last_run[name]
            @logger.debug("Collection #{name} scheduled to run at #{next_run}.")
          end
        end
      end

      private def remove_unseen_actions
        (@last_run.keys - @seen_actions).each { |name| @last_run.delete(name) }
        @seen_actions.clear
      end
    end
  end
end