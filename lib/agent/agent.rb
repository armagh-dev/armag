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
require 'armagh/action_errors'

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

    def get_splitter(action_name, docspec_name)
      @action_manager.get_splitter(action_name, docspec_name)
    end

    def create_document(action_doc)
      # TODO agent#create_document: throw an error if insert fails (not unique, too large, etc)
      docspec = action_doc.docspec
      pending_actions = @action_manager.get_action_names_for_docspec(docspec)
      Document.create(docspec.type, action_doc.draft_content, action_doc.published_content, action_doc.meta,
                      pending_actions, docspec.state, action_doc.id, true)
    end

    def edit_document(id, docspec)
      # TODO agent#edit_document, throw an error if insert fails (too large, etc)
      if block_given?
        Document.modify_or_create(id, docspec.type, docspec.state) do |doc|
          edit_or_create(id, docspec, doc) do |doc|
            yield doc
          end
        end
      else
        @logger.warn "edit_document called for document #{id} but not block was given.  Ignoring."
      end
    end

    # returns true if the document was modified or created, false if the document was skipped because it was locked.
    def edit_document!(id, docspec)
      # TODO agent#edit_document!: hrow an error if insert fails (too large, etc)
      if block_given?
        result = Document.modify_or_create!(id, docspec.type, docspec.state) do |doc|
          edit_or_create(id, docspec, doc) do |doc|
            yield doc
          end
        end
      else
        @logger.warn "edit_document! called for document #{id} but not block was given.  Ignoring."
        result = false
      end
      result
    end

    private def edit_or_create(id, docspec, doc)
      if doc
        action_doc = doc.to_action_document
        initial_docspec = action_doc.docspec

        yield action_doc

        new_docspec = action_doc.docspec

        raise ActionErrors::DocSpecError.new "Document's type is not changeable while editing.  Only state is." unless initial_docspec.type == new_docspec.type
        raise ActionErrors::DocSpecError.new "Document's states can only be changed to #{DocState::READY} or #{DocState::WORKING} while editing." unless new_docspec.state == DocState::READY || new_docspec.state == DocState::WORKING

        doc.update_from_action_document(action_doc)

        unless initial_docspec == new_docspec
          pending_actions = @action_manager.get_action_names_for_docspec(new_docspec)
          doc.clear_pending_actions
          doc.add_pending_actions pending_actions
        end
      else
        action_doc = ActionDocument.new(id, {}, {}, {}, docspec, true)
        yield action_doc
        pending_actions = @action_manager.get_action_names_for_docspec(docspec)
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
      # TODO fix split logging of error in agent#run
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
      new_config = AgentStatus.get_config(@agent_status, @last_config_timestamp)
      apply_config(new_config) if new_config
    end

    private def apply_config(config)
      change_log_level(config['log_level'])
      @action_manager.set_available_actions(config['available_actions'])
      @last_config_timestamp = config['timestamp']
      @logger.debug "Updated configuration to #{config}"
    end

    private def execute
      doc = Document.get_for_processing

      if doc
        @backoff.reset

        doc.pending_actions.delete_if do |name|
          current_action = @action_manager.get_action(name)

          @logger.error "Document: #{doc.id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined." unless current_action
          report_status(doc, current_action)

          if current_action
            begin
              @logger.debug "Executing #{name} on document #{doc.id}"
              Dir.mktmpdir do |tmp_dir|
                Dir.chdir(tmp_dir) do
                  execute_action(current_action, doc)
                end
              end
            rescue => e
              @logger.error "Error while executing action '#{name}'"
              # TODO fix split logging of error in agent#execute
              @logger.error e
              doc.add_failed_action(name, e)
            end
          else
            # This could happen while actions are propagating through the system
            doc.add_failed_action(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end
          true # Always remove this action from pending
        end
        doc.finish_processing unless doc.deleted?
      else
        report_status(doc, nil)
        @backoff.interruptible_backoff { !@running }
      end
    end

    # returns new actions that should be added to the iterator
    private def execute_action(action, doc)
      action_doc = doc.to_action_document
      case action
        when CollectAction
          action.collect
          # TODO agent#execute_action Don't delete here.  Instead, we should store the number of files collected (either through this or a splitter called by this) Essentially, number of writes to the database.
          doc.delete
        when ParseAction
          action.parse action_doc
          doc.delete
        when PublishAction
          # TODO agent#execute_action: Publish should actually publish to an external collection So we are working in the local documents collection, but publish applies this to the remote collection
          action.publish action_doc
          doc.meta = action_doc.meta
          doc.published_content = action_doc.draft_content
          doc.draft_content = {}
          doc.state = DocState::PUBLISHED
          doc.add_pending_actions(@action_manager.get_action_names_for_docspec(DocSpec.new(doc.type, doc.state)))
        when SubscribeAction
          action.subscribe action_doc
          doc.draft_content = action_doc.draft_content
          doc.meta = action_doc.meta
        when Action
          @logger.error "#{action.name} is an unknown action type."
        else
          @logger.error "#{action} is an not an action."
      end
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
