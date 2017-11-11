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

require 'socket'

require 'armagh/documents'
require 'armagh/actions/collect'
require 'armagh/support/cron'

require_relative 'interruptible_sleep'
require_relative '../logging'
require_relative '../document/action_trigger_document'
require_relative '../document/trigger_manager_semaphore_document'
require_relative '../actions/workflow_set'
require_relative '../status/agent_status'

module Armagh
  module Utils
    class ScheduledActionTrigger
      attr_reader :logger

      def initialize( workflow_set )
        @workflow_set = workflow_set
        @running = false
        @logger = Logging.set_logger('Armagh::Application::ScheduledActionTrigger')

        @last_run = {}
        @seen_actions = []

        TriggerManagerSemaphoreDocument.ensure_one_exists
        @semaphore_doc = nil
      end

      def start
        @thread ||= Thread.new { run }
        @thread.abort_on_exception = true
        @thread_id = "#{Socket.gethostname}:#{@thread.object_id}"
      end

      def stop
        begin
          @semaphore_doc.save( true, self ) if @semaphore_doc
        rescue => e
          # can't log from a trap context
        end
        Thread.new {@logger.debug 'Stopping Scheduled Action Trigger'}.join
        @running = false
        @thread.join if @thread
        @thread = nil
        @thread_id = nil
      end

      def running?
        @running && @thread.alive?
      end

      def signature
        "armagh-scheduled-action-trigger-#{@thread_id}"
      end

      def responsible_for_triggering_actions

        if @semaphore_doc && !@semaphore_doc.locked_by_anyone?
          @semaphore_doc = nil
        end

        unless @semaphore_doc
          @semaphore_doc = TriggerManagerSemaphoreDocument.find_one_locked(
              { 'name' => TriggerManagerSemaphoreDocument::NAME },
              self
          )
          # ignore the seen_actions and last_run values from the db intentionally.
          # they're recorded for the admin's review, but not to communicate state
          # from one ScheduledActionTrigger on one server to another.  In the time
          # btwn one shutting down and the other picking up the task (and the document),
          # the workflows may have changed, rendering the data invalid.
        end

        @semaphore_doc
      end

      def trigger_individual_action(config)
        @logger.debug "Triggering #{config.action.name}"
        docspec = config.input.docspec
        pending_actions = @workflow_set.actions_names_handling_docspec(docspec)
        ActionTriggerDocument.ensure_one_exists(state: docspec.state, type: docspec.type, pending_actions: pending_actions, logger: @logger)
      rescue => e
        Logging.ops_error_exception(@logger, e, 'Document insertion failed.')
      end

      private def run
        @logger.debug 'Starting scheduled action trigger.'
        @running = true
        while @running
          begin
            if responsible_for_triggering_actions
              trigger_actions
              remove_unseen_actions
              update_status_in_db
            end
          rescue => e
            Logging.dev_error_exception(@logger, e, 'Scheduled action trigger failed.')
          end
          InterruptibleSleep.interruptible_sleep(1) { !running? }
        end

        Thread.new {@logger.info 'Scheduled Action Trigger Stopped'}.join
      end

      private def trigger_actions

        actions_to_trigger = @workflow_set.collect_action_configs + @workflow_set.utility_action_configs

        actions_to_trigger.each do |config|
          next unless config.action.active

          now = Time.now
          name = config.action.name

          @seen_actions << name
          schedule = config.respond_to?(:collect) ? config.collect.schedule : config.utility.schedule

          next unless schedule

          @last_run[name] ||= now
          next_run = Armagh::Support::Cron.next_execution_time(schedule, @last_run[name])
          if now >= next_run
            trigger_individual_action(config)
            @last_run[name] = now
            @logger.debug("Action #{name} scheduled to run at #{Armagh::Support::Cron.next_execution_time(schedule, now)}.")
          elsif now == @last_run[name]
            @logger.debug("Action #{name} scheduled to run at #{next_run}.")
          end
        end
      end

      private def remove_unseen_actions
        (@last_run.keys - @seen_actions).each { |name| @last_run.delete(name) }
        @seen_actions.clear
      end

      private def update_status_in_db
        @semaphore_doc.last_run = @last_run
        @semaphore_doc.seen_actions = @seen_actions
        @semaphore_doc.save( false, self )
      end
    end
  end
end