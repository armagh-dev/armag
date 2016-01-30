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

require_relative '../action/action_manager'
require_relative '../document/document'
require_relative '../ipc'
require_relative '../logging/global_logger'
require_relative '../utils/processing_backoff'

module Armagh
  class Agent
    attr_reader :uuid

    LOG_DIR = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh'
    LOG_LOCATION = File.join(LOG_DIR, '%s.log')

    def initialize
      @uuid = "Agent-#{SecureRandom.uuid}"
      log_location = LOG_LOCATION % @uuid
      @logger = Logging::GlobalLogger.new(@uuid, log_location, 'daily')

      @running = false

      @action_manager = ActionManager.new(self, @logger)

      @backoff = Utils::ProcessingBackoff.new
      @backoff.logger = @logger
    end

    def start
      connect_agent_status
      update_config

      @logger.info 'Starting'
      @running = true
      run
    end

    def stop
      if @running
        Thread.new { @logger.info 'Stopping' }
        @client.stop_service if @client
        @running = false
      end
    end

    def running?
      @running
    end

    def insert_document(id, content, meta, state)
      # TODO batching
      if @current_action
        type = @current_action.output_doctype
        pending_actions = @action_manager.get_action_instance_names(type)
        Document.create(type, content, meta, pending_actions, state, id)
      else
        @logger.error 'Document insert can only be called by an action'
      end
    end

    def update_document(id, content, meta, state)
      # TODO batching
      if @current_action
        type = @current_action.output_doctype

        doc = Document.find(id)
        doc.type = type
        doc.content = content
        doc.meta = meta
        doc.add_pending_actions(@action_manager.get_action_instance_names(type))
        doc.state = state
        doc.save
      else
        @logger.error 'Document update can only be called by an action'
      end
    end

    def insert_or_update_document(id, content, meta, state)
      # TODO batching
      if @current_action
        doc = Document.find(id)
        if doc
          type = @current_action.output_doctype

          doc.type = type
          doc.content = content
          doc.meta = meta
          doc.add_pending_actions(@action_manager.get_action_instance_names(type))
          doc.state = state
          doc.save
        else
          insert_document(id, content, meta, state)
        end
      else
        @logger.error 'Document insertion or update can only be called by an action'
      end
    end

    # Blocking modify.  If the document is locked, block until unlocked.  If the document doesn't exist, doesn't yield
    def modify(id)
      if block_given?
        result = Document.modify(id) do |doc|
          if doc
            action_doc = doc.to_action_document
            yield action_doc
            doc.update_from_action_document(action_doc)
          end
        end
      else
        @logger.warn "Modify called for document #{id} but not block was given.  Ignoring."
        result = false
      end
      result
    end

    # Non-Blocking fetch.  If the document is locked or doesn't exist, doesn't yield
    def modify!(id)
      if block_given?
        result = Document.modify!(id) do |doc|
          if doc
            action_doc = doc.to_action_document
            yield action_doc
            doc.update_from_action_document(action_doc)
          end
        end
      else
        @logger.warn "Modify called for document #{id} but not block was given.  Ignoring."
        result = false
      end
      result
    end

    private def run
      while @running
        update_config
        execute
      end

      @logger.info 'Terminated'
    rescue => e
      @logger.error 'An unexpected error occurred.'
      @logger.error e
    end

    private; def connect_agent_status # ; is a workaround for yard and sub/gsub (https://github.com/lsegal/yard/issues/888)
      client_uri = IPC::DRB_CLIENT_URI % @uuid
      socket_file = client_uri.sub("drbunix://",'')

      if File.exists? socket_file
        @logger.debug "Deleting #{socket_file}.  This may have existed already due to a previous crash of the agent."
        File.delete socket_file
      end

      @client = DRb.start_service(client_uri)
      @agent_status = DRbObject.new_with_uri(IPC::DRB_URI)
    end

    private def update_config
      new_config = AgentStatus.get_config(@agent_status)

      if @last_config_timestamp.nil? || new_config['timestamp'] > @last_config_timestamp
        @config = new_config
        apply_config(@config)
        @last_config_timestamp = @config['timestamp']
      end
    end

    private def apply_config(config)
      change_log_level(config['log_level'])
      @action_manager.set_available_action_instances(config['available_actions'])
      @logger.debug "Updated configuration to #{config}"
    end

    private def execute
      doc = Document.get_for_processing

      if doc
        @backoff.reset

        action_names = doc.pending_actions

        action_names.each do |name|
          @current_action = @action_manager.get_action_from_name(name)

          @logger.error "Document: #{doc.id} had an invalid action.  Please make sure all pending actions of this document are defined." unless @current_action
          report_status(doc, @current_action)

          if @current_action
            begin
              @logger.debug "Executing #{name} on document #{doc.id}"
              @current_action.execute(doc)
            rescue => e
              @logger.error "Error while executing action '#{name}'"
              @logger.error e
              doc.add_failed_action(name, e)
            ensure
              doc.remove_pending_action(name)
            end
          else
            # This could happen while actions are propagating through the system
            doc.add_failed_action(name, 'Undefined action')
            doc.remove_pending_action(name)

            report_status(doc, @current_action)
            @backoff.interruptible_backoff { !@running }
          end
        end
        doc.finish_processing
        @current_action = nil
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
