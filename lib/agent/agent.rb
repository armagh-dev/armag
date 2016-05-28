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
require 'log4r'
require 'securerandom'
require 'tmpdir'

require 'armagh/actions'
require 'armagh/documents'
require 'armagh/action_errors'

require_relative '../action/action_manager'
require_relative '../document/document'
require_relative '../ipc'
require_relative '../utils/processing_backoff'

module Armagh
  class Agent
    attr_reader :uuid

    def initialize
      @uuid = "Agent-#{SecureRandom.uuid}"
      @logger = Log4r::Logger["Armagh::Application::Agent::#{@uuid}"] || Log4r::Logger.new("Armagh::Application::Agent::#{@uuid}")

      @running = false

      @action_manager = ActionManager.new(self, @logger)

      @backoff = Utils::ProcessingBackoff.new
      @backoff.logger = @logger

      @num_creates = 0
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
      docspec = action_doc.docspec
      raise ActionErrors::DocumentError, "Cannot create document '#{action_doc.id}'.  It is the same document that was passed into the action." if action_doc.id == @current_doc.id
      pending_actions = @action_manager.get_action_names_for_docspec(docspec)
      Document.create(type: docspec.type, draft_content: action_doc.draft_content, published_content: action_doc.published_content,
                      draft_metadata: action_doc.draft_metadata, published_metadata: action_doc.published_metadata,
                      pending_actions: pending_actions, state: docspec.state, id: action_doc.id, new: true)
      @num_creates += 1
    end

    def edit_document(id, docspec)
      raise ActionErrors::DocumentError, "Cannot edit document '#{id}'.  It is the same document that was passed into the action." if id == @current_doc.id
      if block_given?
        Document.modify_or_create(id, docspec.type, docspec.state, @running, @logger) do |doc|
          edit_or_create(id, docspec, doc) do |doc|
            yield doc
          end
        end
      else
        @logger.warn "edit_document called for document '#{id}' but no block was given.  Ignoring."
      end
    end

    private def edit_or_create(id, docspec, doc)
      if doc
        action_doc = doc.to_action_document
        initial_docspec = action_doc.docspec

        yield action_doc

        new_docspec = action_doc.docspec

        raise ActionErrors::DocSpecError, "Document '#{id}' type is not changeable while editing.  Only state is." unless initial_docspec.type == new_docspec.type
        raise ActionErrors::DocSpecError, "Document '#{id}' state can only be changed from #{DocState::WORKING} to #{DocState::READY}." unless ((initial_docspec.state == new_docspec.state) || (initial_docspec.state == DocState::WORKING && new_docspec.state == DocState::READY))

        # Output can only equal to input state unless input was working and output is ready.
        doc.update_from_action_document(action_doc)

        unless initial_docspec == new_docspec
          pending_actions = @action_manager.get_action_names_for_docspec(new_docspec)
          doc.clear_pending_actions
          doc.add_pending_actions pending_actions
        end
      else
        action_doc = ActionDocument.new(id: id, draft_content: {}, published_content: {}, draft_metadata: {},
                                        published_metadata: {}, docspec: docspec, new: true)

        yield action_doc

        new_docspec = action_doc.docspec

        raise ActionErrors::DocSpecError, "Document '#{id}' type is not changeable while editing.  Only state is." unless docspec.type == new_docspec.type
        raise ActionErrors::DocSpecError, "Document '#{id}' state can only be changed from #{DocState::WORKING} to #{DocState::READY}." unless ((docspec.state == new_docspec.state) || (docspec.state == DocState::WORKING && new_docspec.state == DocState::READY))

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
      Logging.error_exception(@logger, e, 'An unexpected error occurred.')
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
      if new_config
        apply_config(new_config)
      else
        @logger.debug 'Ignoring agent configuration update.'
      end

    end

    private def apply_config(config)
      change_log_level(config['log_level'])
      @action_manager.set_available_actions(config['available_actions'])
      @last_config_timestamp = config['timestamp']
      @logger.debug "Updated configuration to #{config}"
    end

    private def execute
      @current_doc = Document.get_for_processing

      if @current_doc
        @backoff.reset

        @current_doc.pending_actions.delete_if do |name|
          current_action = @action_manager.get_action(name)

          @logger.error "Document: #{@current_doc.id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined." unless current_action
          report_status(@current_doc, current_action)

          if current_action
            begin
              @logger.debug "Executing #{name} on document '#{@current_doc.id}'."
              Dir.mktmpdir do |tmp_dir|
                Dir.chdir(tmp_dir) do
                  execute_action(current_action, @current_doc)
                end
              end
            rescue Exception => e
              Logging.error_exception(@logger, e, "Error while executing action '#{name}'.")
              @current_doc.add_failed_action(name, e)
            end
          else
            # This could happen while actions are propagating through the system
            @current_doc.add_failed_action(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end
          true # Always remove this action from pending
        end
        @current_doc.finish_processing
      else
        @logger.debug 'No document found for processing.'
        report_status(@current_doc, nil)
        @backoff.interruptible_backoff { !@running }
      end
      @current_doc = nil
    end

    # returns new actions that should be added to the iterator
    private def execute_action(action, doc)
      case action
        when CollectAction
          @num_creates = 0
          action.collect
          doc.draft_metadata.merge!({
            'docs_collected' => @num_creates
          })
          doc.mark_archive
        when ParseAction
          action_doc = doc.to_action_document
          action.parse action_doc
          doc.mark_delete
        when PublishAction
          action_doc = doc.to_publish_action_document
          action.publish action_doc
          doc.published_metadata = action_doc.draft_metadata
          doc.published_content = action_doc.draft_content
          doc.draft_metadata = {}
          doc.draft_content = {}
          doc.state = DocState::PUBLISHED
          doc.add_pending_actions(@action_manager.get_action_names_for_docspec(DocSpec.new(doc.type, doc.state)))
          doc.mark_publish
        when ConsumeAction
          action_doc = doc.to_action_document
          action.consume action_doc
          doc.draft_content = action_doc.draft_content
          doc.draft_metadata = action_doc.draft_metadata
        when Action
          @logger.error "#{action.name} is an unknown action type."
        else
          @logger.error "#{action} is an not an action."
      end
    end

    private def change_log_level(level)
      unless @logger.level == level
        @logger.any "Changing log level to #{@logger.levels[level]}"
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
