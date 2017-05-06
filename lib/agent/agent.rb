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

require 'drb/unix'
require 'securerandom'
require 'tmpdir'

require 'configh'

require 'armagh/actions'
require 'armagh/documents'
require 'armagh/support/random'

require_relative '../logging'
require_relative '../document/document'
require_relative '../ipc'
require_relative '../utils/archiver'
require_relative '../utils/processing_backoff'


module Armagh
  class Agent
    include Configh::Configurable

    define_parameter name: 'log_level', type: 'populated_string', description: 'Logging level for agents', required: true, default: 'info', group: 'agent'
    define_group_validation_callback callback_class: Agent, callback_method: :report_validation_errors

    attr_reader :uuid

    def initialize(agent_config, workflow)
      @config = agent_config
      @workflow = workflow

      @uuid = "agent-#{SecureRandom.uuid}"
      @logger = Logging.set_logger("Armagh::Application::Agent::#{@uuid}")
      Logging.set_level(@logger, @config.agent.log_level)

      @running = false

      @backoff = Utils::ProcessingBackoff.new
      @backoff.logger = @logger

      @num_creates = 0
      @archives_for_collect = []
      @archiver = Utils::Archiver.new(@logger)
    end

    def start
      connect_agent_status

      @logger.info 'Starting'
      @running = true
      run
    end

    def stop
      if @running
        Thread.new { @logger.info 'Stopping Agent' }.join
        @running = false
      end
    end

    def running?
      @running
    end

    def instantiate_divider(docspec)
      @workflow.instantiate_divider(docspec, self, @logger, Connection.config)
    end

    def create_document(action_doc)
      docspec = action_doc.docspec
      raise Documents::Errors::DocumentError, "Cannot create document '#{action_doc.document_id}'.  It is the same document that was passed into the action." if action_doc.document_id == @current_doc.document_id
      pending_actions = @workflow.get_action_names_for_docspec(docspec)
      collection_task_ids = []
      collection_task_ids.concat @collection_task_ids if @collection_task_ids
      archive_files = []
      archive_files.concat @archive_files if @archive_files
      Document.create(type: docspec.type,
                      content: action_doc.content,
                      metadata: action_doc.metadata,
                      pending_actions: pending_actions,
                      state: docspec.state,
                      document_id: action_doc.document_id,
                      collection_task_ids: collection_task_ids,
                      archive_files: archive_files,
                      title: action_doc.title,
                      copyright: action_doc.copyright,
                      document_timestamp: action_doc.document_timestamp,
                      display: action_doc.display,
                      source: action_doc.source,
                      new: true,
                      logger: @logger)
      @num_creates += 1
    rescue Connection::DocumentUniquenessError => e
      raise Documents::Errors::DocumentUniquenessError.new(e.message)
    rescue Connection::DocumentSizeError => e
      raise Documents::Errors::DocumentSizeError.new(e.message)
    end

    def edit_document(document_id, docspec)
      raise Documents::Errors::DocumentError, "Cannot edit document '#{document_id}'.  It is the same document that was passed into the action." if document_id == @current_doc.document_id
      if block_given?
        Document.modify_or_create(document_id, docspec.type, docspec.state, @running, @uuid, @logger) do |doc|
          edit_or_create(document_id, docspec, doc) do |doc|
            yield doc
          end
        end
      else
        @logger.dev_warn "edit_document called for document '#{document_id}' but no block was given.  Ignoring."
      end
    rescue Connection::DocumentUniquenessError => e
      raise Documents::Errors::DocumentUniquenessError.new(e.message)
    rescue Connection::DocumentSizeError => e
      raise Documents::Errors::DocumentSizeError.new(e.message)
    end

    def get_existing_published_document(action_doc)
      doc = Document.find(action_doc.document_id, action_doc.docspec.type, Documents::DocState::PUBLISHED)
      doc ? doc.to_published_document : nil
    end

    def log_debug(logger_name, msg = nil)
      logger = get_logger(logger_name)
      if block_given?
        logger.debug { yield }
      else
        logger.debug msg
      end
    end

    def log_info(logger_name, msg = nil)
      logger = get_logger(logger_name)
      if block_given?
        logger.info { yield }
      else
        logger.info msg
      end
    end

    def notify_ops(logger_name, action_name, error)
      @current_doc.add_ops_error(action_name, error)
      logger = get_logger(logger_name)
      error.is_a?(Exception) ? Logging.ops_error_exception(logger, error, 'Notify Ops') : logger.ops_error(error)
    end

    def notify_dev(logger_name, action_name, error)
      @current_doc.add_dev_error(action_name, error)
      logger = get_logger(logger_name)
      error.is_a?(Exception) ? Logging.dev_error_exception(logger, error, 'Notify Dev') : logger.dev_error(error)
    end

    def get_logger(logger_name)
      Logging.set_logger logger_name
    end

    def archive(logger_name, action_name, file_path, archive_data)
      archive_file = @archiver.archive_file(file_path, archive_data)
      @archives_for_collect << archive_file
      @archive_files = [archive_file]
    rescue Utils::Archiver::ArchiveError => e
      notify_dev(logger_name, action_name, e)
    rescue Support::SFTP::SFTPError => e
      notify_ops(logger_name, action_name, e)
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
        doc.collection_task_ids.concat @collection_task_ids if @collection_task_ids
        doc.archive_files.concat @archive_files if @archive_files

        unless initial_docspec == new_docspec
          pending_actions = @workflow.get_action_names_for_docspec(new_docspec)
          doc.clear_pending_actions
          doc.add_pending_actions pending_actions
        end
      else
        action_doc = Documents::ActionDocument.new(document_id: document_id,
                                                   content: {},
                                                   metadata: {},
                                                   docspec: docspec,
                                                   source: {},
                                                   title: nil,
                                                   copyright: nil,
                                                   document_timestamp: nil,
                                                   new: true)

        yield action_doc

        new_docspec = action_doc.docspec
        new_id = action_doc.document_id

        raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{document_id}' to '#{new_id}.  IDs can only be changed from a publisher." unless document_id == new_id
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' type is not changeable while editing.  Only state is." unless docspec.type == new_docspec.type
        raise Documents::Errors::DocSpecError, "Document '#{document_id}' state can only be changed from #{Documents::DocState::WORKING} to #{Documents::DocState::READY}." unless ((docspec.state == new_docspec.state) || (docspec.state == Documents::DocState::WORKING && new_docspec.state == Documents::DocState::READY))

        pending_actions = @workflow.get_action_names_for_docspec(docspec)
        new_doc = Document.from_action_document(action_doc, pending_actions)
        new_doc.collection_task_ids.concat @collection_task_ids if @collection_task_ids
        new_doc.archive_files.concat @archive_files if @archive_files
        new_doc.internal_id = doc
        new_doc.save(logger: @logger)
      end
    end

    private def run
      while @running
        execute
      end

      if @client
        @logger.debug 'Stopping internal communication client'
        @client.stop_service
        @logger.debug 'Internal communication client stopped'
      end

      DRb.thread.join
      @logger.info 'Terminated'
    rescue => e
      Logging.dev_error_exception(@logger, e, 'An unexpected error occurred')
    end

    private def connect_agent_status
      client_uri = IPC::DRB_CLIENT_URI % @uuid
      socket_file = client_uri.sub("drbunix://", '')

      if File.exists? socket_file
        @logger.debug "Deleting #{socket_file}.  This may have existed already due to a previous crash of the agent."
        File.delete socket_file
      end

      @client = DRb.start_service(client_uri)

      @agent_status = DRbObject.new_with_uri(IPC::DRB_URI)
    end


    private def execute
      @current_doc = Document.get_for_processing(@uuid)

      if @current_doc
        @backoff.reset

        @current_doc.pending_actions.delete_if do |name|
          if @current_doc.error?
            @logger.info("Skipping further actions on document '#{@current_doc.document_id}' since it has errors.")
            break
          end
          current_action = @workflow.instantiate_action(name, self, @logger, Connection.config)

          @logger.ops_error "Document: #{@current_doc.document_id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined." unless current_action
          report_status(@current_doc, current_action)

          if current_action
            begin
              exec_id = @current_doc.document_id || @current_doc.internal_id
              @logger.debug "Executing #{name} on document '#{exec_id}'."
              start = Time.now
              Dir.mktmpdir do |tmp_dir|
                Dir.chdir(tmp_dir) do
                  execute_action(current_action, @current_doc)
                end
              end
              @logger.debug "Execution of #{name} on document '#{exec_id}' completed in #{Time.now-start} seconds."
            rescue Documents::Errors::DocumentSizeError => e
              Logging.ops_error_exception(@logger, e, "Error while executing action '#{name}' on '#{@current_doc.document_id}'")
              @current_doc.add_ops_error(name, e)
            rescue Exception => e
              Logging.dev_error_exception(@logger, e, "Error while executing action '#{name}' on '#{@current_doc.document_id}'")
              @current_doc.add_dev_error(name, e)
            end
          else
            # This could happen while actions are propagating through the system
            @current_doc.add_ops_error(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end

          @logger.warn "Error executing action '#{name}' on '#{@current_doc.document_id}'.  See document for details." if @current_doc.dev_errors.any? || @current_doc.ops_errors.any?

          true # Always remove this action from pending
        end #delete_if
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
          @collection_task_ids = [doc.document_id]
          @num_creates = 0
          @archives_for_collect.clear
          @archive_files = nil

          if action.config.collect.archive
            @archiver.within_archive_context {action.collect}
          else
            action.collect
          end

          doc.metadata['docs_collected'] = @num_creates
          doc.metadata['archived_files'] = @archives_for_collect unless @archives_for_collect.empty?
          @num_creates == 0 ? doc.mark_delete : doc.mark_collection_history
        when Actions::Split
          @collection_task_ids = doc.collection_task_ids
          @archive_files = doc.archive_files
          action_doc = doc.to_action_document
          action.split action_doc
          doc.mark_delete
        when Actions::Publish
          timestamp = Time.now
          @collection_task_ids = doc.collection_task_ids
          @archive_files = doc.archive_files
          allowed_id_change = true
          action_doc = doc.to_action_document
          action.publish action_doc
          doc.document_id = action_doc.document_id || Armagh::Support::Random.random_id
          doc.metadata = action_doc.metadata
          doc.content = action_doc.content
          doc.title = action_doc.title
          doc.copyright = action_doc.copyright
          doc.document_timestamp = action_doc.document_timestamp || timestamp
          doc.display = action_doc.display

          published_doc = doc.get_published_copy
          if published_doc
            doc.created_timestamp = published_doc.created_timestamp

            doc.dev_errors.merge!(published_doc.dev_errors) { |_key, v1, v2| v2 + v1 }
            doc.ops_errors.merge!(published_doc.ops_errors) { |_key, v1, v2| v2 + v1 }
            doc.collection_task_ids.unshift(*(published_doc.collection_task_ids))
            doc.archive_files.unshift(*(published_doc.archive_files))

            doc.title ||= published_doc.title
            doc.copyright ||= published_doc.copyright
            doc.published_id = published_doc.internal_id
            doc.display ||= published_doc.display
            doc.source ||= published_doc.source
          end

          doc.published_timestamp = timestamp
          doc.state = action.config.output.docspec.state unless doc.error?
          doc.add_pending_actions(@workflow.get_action_names_for_docspec(Documents::DocSpec.new(doc.type, doc.state)))
          doc.mark_publish
        when Actions::Consume
          @collection_task_ids = doc.collection_task_ids
          @archive_files = doc.archive_files
          published_doc = doc.to_published_document
          action.consume published_doc
          # Only metadata can be changed
          doc.metadata = published_doc.metadata
        when Actions::Action
          @logger.dev_error "#{action.name} is an unknown action type."
        else
          @logger.dev_error "#{action} is not an action."
      end
      raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{initial_id}' to '#{doc.document_id}.  IDs can only be changed from a publisher." unless initial_id == doc.document_id || allowed_id_change
    ensure
      @num_creates = 0
      @archives_for_collect.clear
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

      @logger.debug "Reporting Status #{status['status']}"

      @agent_status.report_status(@uuid, status)
    end

    def Agent.report_validation_errors(candidate_config)
      errors = nil
      unless Logging.valid_level?(candidate_config.agent.log_level)
        errors = "Log level must be one of #{ Logging.valid_log_levels.join(", ")}"
      end
      errors
    end
  end
end
