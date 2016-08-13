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

require_relative '../logging'
require_relative '../action/action_manager'
require_relative '../document/document'
require_relative '../ipc'
require_relative '../utils/processing_backoff'
require_relative '../utils/encoding_helper'

module Armagh
  class Agent
    attr_reader :uuid

    def initialize
      @uuid = "Agent-#{SecureRandom.uuid}"
      @logger = Logging.set_logger("Armagh::Application::Agent::#{@uuid}")

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

    def get_divider(action_name, docspec_name)
      @action_manager.get_divider(action_name, docspec_name)
    end

    def create_document(action_doc)
      docspec = action_doc.docspec
      raise Documents::Errors::DocumentError, "Cannot create document '#{action_doc.document_id}'.  It is the same document that was passed into the action." if action_doc.document_id == @current_doc.document_id
      pending_actions = @action_manager.get_action_names_for_docspec(docspec)
      collection_task_ids = []
      collection_task_ids << @collection_task_id if @collection_task_id
      Document.create(type: docspec.type,
                      content: action_doc.content,
                      metadata: action_doc.metadata,
                      pending_actions: pending_actions,
                      state: docspec.state,
                      document_id: action_doc.document_id,
                      collection_task_ids: collection_task_ids,
                      title: action_doc.title,
                      copyright: action_doc.copyright,
                      document_timestamp: action_doc.document_timestamp,
                      source: action_doc.source, new: true, logger: @logger)
      @num_creates += 1
    end

    def edit_document(document_id, docspec)
      raise Documents::Errors::DocumentError, "Cannot edit document '#{document_id}'.  It is the same document that was passed into the action." if document_id == @current_doc.document_id
      if block_given?
        Document.modify_or_create(document_id, docspec.type, docspec.state, @running, @logger) do |doc|
          edit_or_create(document_id, docspec, doc) do |doc|
            yield doc
          end
        end
      else
        @logger.dev_warn "edit_document called for document '#{document_id}' but no block was given.  Ignoring."
      end
    end

    def get_existing_published_document(action_doc)
      doc = Document.find(action_doc.document_id, action_doc.docspec.type, Documents::DocState::PUBLISHED)
      doc ? doc.to_published_document : nil
    end

    def log_debug(logger_name, msg = nil)
      logger = Logging.set_logger(logger_name)
      if block_given?
        logger.debug { yield }
      else
        logger.debug msg
      end
    end

    def log_info(logger_name, msg = nil)
      logger = Logging.set_logger(logger_name)
      if block_given?
        logger.info { yield }
      else
        logger.info msg
      end
    end

    def notify_ops(action_name, error)
      @current_doc.add_ops_error(action_name, error)
    end

    def notify_dev(action_name, error)
      @current_doc.add_dev_error(action_name, error)
    end

    def fix_encoding(logger_name, object, proposed_encoding)
      logger = Logging.set_logger(logger_name)
      Utils::EncodingHelper.fix_encoding(object, proposed_encoding: proposed_encoding, logger: logger)
    end

    private def edit_or_create(document_id, docspec, doc)
      if doc.is_a? Document
        action_doc = doc.to_action_document
        initial_docspec = action_doc.docspec

        yield action_doc

        new_docspec = action_doc.docspec
        new_id = action_doc.document_id

        raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{document_id}' to '#{new_id}.  IDs can only be changed from a publisher." unless document_id == new_id
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' type is not changeable while editing.  Only state is." unless initial_docspec.type == new_docspec.type
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' state can only be changed from #{Documents::DocState::WORKING} to #{Documents::DocState::READY}." unless ((initial_docspec.state == new_docspec.state) || (initial_docspec.state == Documents::DocState::WORKING && new_docspec.state == Documents::DocState::READY))

        doc.update_from_draft_action_document(action_doc)
        doc.collection_task_ids << @collection_task_id if @collection_task_id

        unless initial_docspec == new_docspec
          pending_actions = @action_manager.get_action_names_for_docspec(new_docspec)
          doc.clear_pending_actions
          doc.add_pending_actions pending_actions
        end
      else
        action_doc = Documents::ActionDocument.new(document_id: document_id, content: {}, metadata: {}, docspec: docspec, source: {}, new: true)

        yield action_doc

        new_docspec = action_doc.docspec
        new_id = action_doc.document_id

        raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{document_id}' to '#{new_id}.  IDs can only be changed from a publisher." unless document_id == new_id
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' type is not changeable while editing.  Only state is." unless docspec.type == new_docspec.type
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' state can only be changed from #{Documents::DocState::WORKING} to #{Documents::DocState::READY}." unless ((docspec.state == new_docspec.state) || (docspec.state == Documents::DocState::WORKING && new_docspec.state == Documents::DocState::READY))

        pending_actions = @action_manager.get_action_names_for_docspec(docspec)
        new_doc = Document.from_action_document(action_doc, pending_actions)
        new_doc.collection_task_ids << @collection_task_id if @collection_task_id
        new_doc.internal_id = doc
        new_doc.save(logger: @logger)
      end
    end

    private def run
      while @running
        update_config
        execute
      end

      @logger.info 'Terminated'
    rescue => e
      Logging.dev_error_exception(@logger, e, 'An unexpected error occurred')
    end

    private def connect_agent_status
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

          @logger.ops_error "Document: #{@current_doc.document_id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined." unless current_action
          report_status(@current_doc, current_action)

          if current_action
            begin
              @logger.debug "Executing #{name} on document '#{@current_doc.document_id}'."
              Dir.mktmpdir do |tmp_dir|
                Dir.chdir(tmp_dir) do
                  execute_action(current_action, @current_doc)
                end
              end
            rescue Documents::Errors::DocumentSizeError => e
              Logging.ops_error_exception(@logger, e, "Error while executing action '#{name}'")
              @current_doc.add_ops_error(name, e)
            rescue Exception => e
              Logging.dev_error_exception(@logger, e, "Error while executing action '#{name}'")
              @current_doc.add_dev_error(name, e)
            end
          else
            # This could happen while actions are propagating through the system
            @current_doc.add_ops_error(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end

          @logger.dev_error "Error executing action '#{name}' on '#{@current_doc.document_id}'.  See document for details." if @current_doc.dev_errors.any?
          @logger.ops_error "Error executing action '#{name}' on '#{@current_doc.document_id}'.  See document for details." if @current_doc.ops_errors.any?

          true # Always remove this action from pending
        end
        @current_doc.finish_processing(@logger)
      else
        @logger.debug 'No document found for processing.'
        report_status(@current_doc, nil)
        @backoff.interruptible_backoff { !@running }
      end
      @current_doc = nil
    end

    # returns new actions that should be added to the iterator
    private def execute_action(action, doc)
      initial_id = doc.document_id
      allowed_id_change = false
      case action
        when Actions::Collect
          @collection_task_id = doc.document_id
          @num_creates = 0
          action.collect
          doc.metadata.merge!({
            'docs_collected' => @num_creates
          })
          doc.mark_archive
          @num_creates = 0
        when Actions::Split
          @collection_task_id = doc.collection_task_ids.last
          action_doc = doc.to_action_document
          action.split action_doc
          doc.mark_delete
        when Actions::Publish
          timestamp = Time.now
          @collection_task_id = doc.collection_task_ids.last
          allowed_id_change = true
          action_doc = doc.to_action_document
          action.publish action_doc
          doc.document_id = action_doc.document_id
          doc.metadata = action_doc.metadata
          doc.content = action_doc.content
          doc.title = action_doc.title
          doc.copyright = action_doc.copyright
          doc.source = {}
          doc.document_timestamp = action_doc.document_timestamp || timestamp

          published_doc = doc.get_published_copy
          if published_doc
            doc.created_timestamp = published_doc.created_timestamp

            doc.dev_errors.merge!(published_doc.dev_errors) { |_key, v1, v2| v2 + v1}
            doc.ops_errors.merge!(published_doc.ops_errors) { |_key, v1, v2| v2 + v1}
            doc.collection_task_ids.unshift(*(published_doc.collection_task_ids))

            doc.title ||= published_doc.title
            doc.copyright ||= published_doc.copyright
            doc.published_id = published_doc.internal_id
          end

          doc.published_timestamp = timestamp
          doc.state = Documents::DocState::PUBLISHED
          doc.add_pending_actions(@action_manager.get_action_names_for_docspec(Documents::DocSpec.new(doc.type, doc.state)))
          doc.mark_publish
        when Actions::Consume
          @collection_task_id = doc.collection_task_ids.last
          published_doc = doc.to_published_document
          action.consume published_doc
          # Only metadata can be changed
          doc.metadata = published_doc.metadata
        when Actions::Action
          @logger.dev_error "#{action.name} is an unknown action type."
        else
          @logger.dev_error "#{action} is an not an action."
      end
      raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{initial_id}' to '#{doc.document_id}.  IDs can only be changed from a publisher." unless initial_id == doc.document_id || allowed_id_change
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
            'document' => doc.document_id,
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
