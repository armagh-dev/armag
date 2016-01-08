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

require 'drb/unix'
require 'securerandom'

require_relative '../ipc'
require_relative '../logging/global_logger'
require_relative '../action/action_manager'
require_relative 'processing_backoff'
require_relative '../document/document'

module Armagh
  class Agent
    attr_reader :uuid

    MAX_BACKOFF_TIME = 500

    LOG_LOCATION = '/var/log/armagh/%s.log'

    def initialize(initial_config = {})
      @uuid = "Agent-#{SecureRandom.uuid}"
      log_location = LOG_LOCATION % @uuid
      @logger = Logging::GlobalLogger.new(@uuid, log_location, 'daily')
      @running = false

      @action_manager = ActionManager.new(self, @logger)
      update_config(initial_config, true)

      client_uri = IPC::DRB_CLIENT_URI % @uuid
      DRb.start_service(client_uri)
      @agent_status = DRbObject.new_with_uri(IPC::DRB_URI)

      @backoff = ProcessingBackoff.new(MAX_BACKOFF_TIME)
      @backoff.logger = @logger

      @logger.debug 'Initialized'
    end

    def start
      @logger.info 'Starting'
      @running = true
      run
    end

    def stop
      if @running
        Thread.new { @logger.info 'Stopping' }
        @running = false
      end
    end

    def running?
      @running
    end

    def insert_document(id, content, meta)
      if @current_action
        type = @current_action.output_doctype
        pending_actions = @action_manager.get_action_instance_names(type)
        Document.create(type, content, meta, pending_actions, id)
      else
        @logger.error 'Document insert can only be called by an action'
      end
    end

    def update_document(id, content, meta)
      if @current_action
        type = @current_action.output_doctype

        doc = Document.find(id)
        doc.type = type
        doc.content = content
        doc.meta = meta
        doc.add_pending_actions(@action_manager.get_action_instance_names(type))
        doc.save
      else
        @logger.error 'Document update can only be called by an action'
      end
    end

    def insert_or_update_document(id, content, meta)
      if @current_action
        doc = Document.find(id)
        if doc
          type = @current_action.output_doctype

          doc.type = type
          doc.content = content
          doc.meta = meta
          doc.add_pending_actions(@action_manager.get_action_instance_names(type))
          doc.save
        else
          insert_document(id, content, meta)
        end
      else
        @logger.error 'Document insertion or update can only be called by an action'
      end
    end

    private
    def run
      while @running
        update_config(AgentStatus.get_config(@agent_status))
        execute
      end

      @logger.info 'Terminated'
    rescue => e
      @logger.error 'An unexpected error occurred.'
      @logger.error e
    end

    private def update_config(config, force = false)
      @last_config_timestamp ||= Time.new(0)

      if config['timestamp'].nil?
        @logger.warn 'Configuration received without a timestamp. A configuration must contain a timestamp.'
      elsif force || (@last_config_timestamp < config['timestamp'])
        change_log_level(config['log_level'])
        @action_manager.set_available_action_instances(config['available_actions'])
        @logger.debug "Updated configuration to #{config}"
        @last_config_timestamp = config['timestamp']
      end
    end

    private def execute
      doc = Document.get_for_processing

      if doc
        action_names = doc.pending_actions

        action_names.each do |name|
          @current_action = @action_manager.get_action_from_name(name)
          @logger.error "Document: #{doc.id} had an invalid action.  Please make sure all pending actions of this document are defined." unless @current_action
          report_status(doc, @current_action)
          if @current_action
            @backoff.reset
            begin
              @current_action.execute(doc)
            rescue => e
              @logger.error "Error while executing action '#{name}'"
              @logger.error e
            end

            doc.remove_pending_action(name)
          else
            # This could happen while actions are propagating through the system
            report_status(doc, @current_action)
            @backoff.interruptible_backoff { !@running }
            report_status(doc, nil)
          end
        end

        doc.save
        doc.unlock
      else
        report_status(doc, nil)
        @backoff.interruptible_backoff { !@running }
      end
    end

    private def change_log_level(level)
      return if level == @logger.level

      if level
        @logger.unknown "Changing log level to #{Logging::GlobalLogger::LEVEL_LOOKUP[level]}"
        @logger.level = level
        @logger.debug 'Log level successfully changed'
      end
    end

    private def report_status(doc, action)
      status = {}

      if doc && action
        @idle_since = nil
        status['task'] = {
            'document' => doc.id,
            'action' => action.name
        }
        status['running_since'] = Time.now
        status['status'] = 'running'
      else
        @idle_since ||= Time.now

        status['status'] = 'idle'
        status['idle_since'] = @idle_since
      end

      status['last_update'] = Time.now

      @logger.info "Reporting Status #{status['status']}"
      @agent_status.report_status(@uuid, status)
    end
  end
end