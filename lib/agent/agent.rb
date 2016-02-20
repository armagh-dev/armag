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
require 'tmpdir'

require 'armagh/actions'
require 'armagh/documents'
require 'armagh/errors'

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

    def get_splitter(action_name, doctype_name)
      @action_manager.get_splitter(action_name, doctype_name)
    end

    def create_document(action_doc)
      # TODO Throw an error if insert fails (not unique, too large, etc)
      doctype = action_doc.doctype
      pending_actions = @action_manager.get_action_names_for_doctype(doctype)
      Document.create(doctype.type, action_doc.draft_content, action_doc.published_content, action_doc.meta,
                      pending_actions, doctype.state, action_doc.id, true)
    end

    def edit_document(id, doctype)
      # TODO Throw an error if insert fails (too large, etc)
      if block_given?
        Document.modify_or_create(id, doctype.type, doctype.state) do |doc|
          edit_or_create(doc)
        end
      else
        @logger.warn "edit_document called for document #{id} but not block was given.  Ignoring."
      end
    end

    # returns true if the document was modified or created, false if the document was skipped because it was locked.
    def edit_document!(id, doctype)
      # TODO Throw an error if insert fails (too large, etc)
      if block_given?
        result = Document.modify_or_create!(id, doctype.type, doctype.state) do |doc|
          edit_or_create(doc)
        end
      else
        @logger.warn "edit_document! called for document #{id} but not block was given.  Ignoring."
        result = false
      end
      result
    end

    private def edit_or_create(doc)
      if doc
        action_doc = doc.to_action_document
        initial_doctype = action_doc.doctype

        yield action_doc

        new_doctype = action_doc.doctype

        raise ActionErrors::DoctypeError.new "Document's type is not changeable while editing.  Only state is." unless initial_doctype.type == new_doctype.type
        raise ActionErrors::DoctypeError.new "Document's states can only be changed to #{DocState::READY} or #{DocState::WORKING} while editing." unless new_doctype.state == DocState::READY || new_doctype.state == DocState::WORKING

        doc.update_from_action_document(action_doc)

        unless initial_doctype == new_doctype
          pending_actions = @action_manager.get_action_names_for_doctype(new_doctype)
          doc.pending_actions.clear
          doc.add_pending_actions pending_actions
        end
      else
        action_doc = ActionDocument.new(id, {}, {}, {}, doctype, true)
        yield action_doc
        pending_actions = @action_manager.get_action_names_for_doctype(doctype)
        new_doc = Document.from_action_document(action_doc, pending_actions)
        new_doc.finish_processing
      end
    end

    private def run
      while @running
        update_config
        execute
      end

      @logger.info 'Terminated'
    rescue => e
      @logger.error 'An unexpected error occurred.'
      # TODO Split error
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
        apply_config(new_config)
        @last_config_timestamp = new_config['timestamp']
      end
    end

    private def apply_config(config)
      change_log_level(config['log_level'])
      @action_manager.set_available_actions(config['available_actions'])
      @logger.debug "Updated configuration to #{config}"
    end

    private def execute
      doc = Document.get_for_processing

      if doc
        @backoff.reset

        doc.pending_actions.delete_if do |name|
          @current_action = @action_manager.get_action(name)

          @logger.error "Document: #{doc.id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined." unless @current_action
          report_status(doc, @current_action)

          if @current_action
            begin
              @logger.debug "Executing #{name} on document #{doc.id}"
              execute_action(@current_action, doc)
            rescue => e
              @logger.error "Error while executing action '#{name}'"
              # TODO Split logging
              @logger.error e
              doc.add_failed_action(name, e)
            ensure
              @current_action = nil
            end
          else
            # This could happen while actions are propagating through the system
            doc.add_failed_action(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end
          true # Always remove this action from pending
        end
        doc.finish_processing if doc
      else
        report_status(doc, nil)
        @backoff.interruptible_backoff { !@running }
      end
    end

    # returns new actions that should be added to the iterator
    private def execute_action(action, doc)
      action_doc = doc.to_action_document
      new_actions = nil
      case
        when action.is_a?(CollectAction)
          Dir.mktmpdir do |tmp_dir|
            Dir.chdir(tmp_dir) do
              action.collect
            end
          end
          # TODO Don't delete here.  Instead, we should store the number of files colellected (either through this or a splitter called by this)
          #   Essentially, number of writes to the database.
          doc.delete
        when action.is_a?(ParseAction)
          action.parse action_doc
          doc.delete
        when action.is_a?(PublishAction)
          # TODO Publish should actually publish to an external collection
          #  So we are working in the local documents collection, but publish applies this to the remote collection
          action.publish action_doc
          doc.meta = action_doc.meta
          doc.published_content = action_doc.draft_content
          doc.draft_content = {}
          doc.state = DocState::PUBLISHED
          doc.add_pending_actions(@action_manager.get_action_names_for_doctype(DocTypeState.new(doc.type, doc.state)))
        when action.is_a?(SubscribeAction)
          action.subscribe action_doc
          doc.draft_content = action_doc.draft_content
          doc.meta = action_doc.meta
        when action.is_a?(CollectionSplitterAction)
          @logger.error "CollectionSplitterAction #{action.name} should have run from the collector.  This is an internal error."
        else
          @logger.error "#{action.name} is an unknown action type."
      end
      new_actions
    end

    private def change_log_level(level)
      unless @logger.level == level
        @logger.unknown "Changing log level to #{Logging::GlobalLogger::LEVEL_LOOKUP[level]}"
        @logger.level = level
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
