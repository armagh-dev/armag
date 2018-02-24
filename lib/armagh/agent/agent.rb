# Copyright 2018 Noragh Analytics, Inc.
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

require 'securerandom'
require 'tmpdir'

require 'configh'

require 'armagh/actions'
require 'armagh/documents'
require 'armagh/logging'
require 'armagh/support/random'

require_relative '../actions/workflow_set'
require_relative '../connection'
require_relative '../document/document'
require_relative '../status'
require_relative '../utils/archiver'
require_relative '../utils/processing_backoff'
require_relative '../utils/action_helper'

module Armagh
  class Agent
    class AbortDocument < RuntimeError; end

    CONFIG_NAME = 'default'

    include Configh::Configurable

    define_parameter name: 'log_level', type: 'string', description: 'Logging level for agents', required: true, options: Armagh::Logging.valid_log_levels.collect{|s| s.encode('UTF-8')}, default: 'info', group: 'agent'

    attr_reader :signature

    def initialize(agent_config, archive_config, workflow_set, hostname)
      @config = agent_config
      @archive_config = archive_config
      @workflow_set = workflow_set
      @hostname = hostname

      @signature = "armagh-agent-#{SecureRandom.uuid}"

      @logger = Logging.set_logger("Armagh::Application::Agent::#{@signature}")
      Logging.set_level(@logger, @config.agent.log_level)

      @running = false
      @shutdown = false

      @backoff = Utils::ProcessingBackoff.new
      @backoff.logger = @logger

      @num_creates = 0
      @archives_for_collect = []
      @archiver = Utils::Archiver.new(@logger, @archive_config)

      Armagh::Document.default_locking_agent = self
    end

    def start
      unless @shutdown
        @running = true
        @logger.info 'Starting'
        run
      end
    end

    def stop
      @shutdown = true
      if @running
        Thread.new { @logger.info 'Stopping Agent' }.join
        @running = false
      end
    end

    def running?
      @running
    end

    def create_document(action_doc)
      docspec = action_doc.docspec
      raise Documents::Errors::DocumentError, "Cannot create document '#{action_doc.document_id}'.  It is the same document that was passed into the action." if action_doc.document_id == @current_doc.document_id
      pending_actions = @workflow_set.actions_names_handling_docspec(docspec)
      collection_task_ids = []
      collection_task_ids.concat @collection_task_ids if @collection_task_ids
      archive_files = []
      archive_files.concat @archive_files if @archive_files
      Document.create_one_unlocked(
          { 'type' => docspec.type,
            'content' => action_doc.content,
            'raw' => action_doc.raw,
            'metadata' => action_doc.metadata,
            'pending_actions' => pending_actions,
            'state' => docspec.state,
            'document_id' => action_doc.document_id,
            'collection_task_ids' => collection_task_ids,
            'archive_files' => archive_files,
            'title' => action_doc.title,
            'copyright' => action_doc.copyright,
            'document_timestamp' => action_doc.document_timestamp,
            'display' => action_doc.display,
            'source' => action_doc.source}
      )
      @num_creates += 1
    rescue Connection::DocumentUniquenessError => e
      raise Documents::Errors::DocumentUniquenessError.new(e.message)
    rescue Connection::DocumentSizeError => e
      raise Documents::Errors::DocumentSizeError.new(e.message)
    end

    def edit_document(document_id, docspec)
      raise Documents::Errors::DocumentError, "Cannot edit document '#{document_id}'.  It is the same document that was passed into the action." if document_id == @current_doc.document_id
      if block_given?
        Document.with_new_or_existing_locked_document(document_id, docspec.type, docspec.state, self) do |doc|
          edit_or_create(document_id, docspec, doc) do |action_doc|
            yield action_doc
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

    def abort
      raise AbortDocument
    end

    def get_existing_published_document(action_doc)
      doc = Document.get_published_copy_read_only(action_doc.document_id, action_doc.docspec.type)
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

    def instantiate_divider(docspec)
      begin
        actions = @workflow_set.instantiate_actions_handling_docspec(docspec, self, @logger)
      rescue Armagh::Actions::ActionInstantiationError => e
        Logging.ops_error_exception(@logger, e, 'Unable to instantiate divide')
        actions = []
      end

      actions.each do |action|
        if action.is_a? Actions::Divide
          log_details = {
            'workflow' => action.config.action.workflow,
            'action' => action.name,
            'action_supertype' => Utils::ActionHelper.get_action_super(action.class),
            'document_internal_id' => ::Logging.mdc['document_internal_id'],
            'additional_info' => action.name
          }
          Logging::set_details(log_details)
          return action
        end
      end
      nil
    end

    private def edit_or_create(document_id, docspec, doc)

      if doc.new_document?
        doc.document_id = document_id
        doc.type = docspec.type
        doc.state = docspec.state
        doc.pending_actions = @workflow_set.actions_names_handling_docspec(docspec)
      end

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
        pending_actions = @workflow_set.actions_names_handling_docspec(new_docspec)
        doc.clear_pending_actions
        doc.add_pending_actions pending_actions
      end
    end

    private def run
      while @running && !@shutdown
        execute
      end

      remove_status
      @logger.info 'Terminated'
    rescue => e
      Logging.dev_error_exception(@logger, e, 'An unexpected error occurred')
    end

    private def execute
      @logger.debug 'Getting document for processing'

      got_one = Document.get_one_for_processing_locked(self, logger: @logger) do |current_doc|

        @current_doc = current_doc
        @backoff.reset

        current_doc.delete_pending_actions_if do |name|

          action_success = true

          if current_doc.error
            @logger.info("Skipping further actions on document '#{current_doc.document_id}' since it has errors.")
            break
          end
          current_action = nil

          begin
            @logger.debug "Instantiating action #{name}"
            current_action = @workflow_set.instantiate_action_named(name, self, @logger)
          rescue Armagh::Actions::ActionInstantiationError
            @logger.ops_error "Document: #{current_doc.document_id} had an invalid action #{name}.  Please make sure all pending actions of this document are defined."
          end

          report_status(current_doc, current_action)
          if current_action
            begin
              if current_action.is_a? Actions::Action
                log_details = {
                  'workflow' => current_action.config.action.workflow,
                  'action' => current_action.name,
                  'action_supertype' => Utils::ActionHelper.get_action_super(current_action.class),
                  'document_internal_id' => current_doc.internal_id,
                  'additional_info' => current_action.name
                }
                Logging::set_details(log_details)
              end

              exec_id = current_doc.document_id || current_doc.internal_id
              @logger.info "Executing #{name} on document '#{exec_id}'."
              start = Time.now
              Dir.mktmpdir do |tmp_dir|
                Dir.chdir(tmp_dir) do
                  execute_action(current_action, current_doc)
                end
              end
              @logger.info "Execution of #{name} on document '#{exec_id}' completed in #{Time.now-start} seconds."
            rescue AbortDocument
              @logger.info "Action #{name} on document '#{exec_id}' was aborted by the action."
              current_doc.mark_abort
            rescue Documents::Errors::DocumentSizeError, Documents::Errors::DocumentRawSizeError => e
              Logging.ops_error_exception(@logger, e, "Error while executing action '#{name}' on '#{current_doc.document_id}'")
              current_doc.add_ops_error(name, e)
            rescue => e
              Logging.dev_error_exception(@logger, e, "Error while executing action '#{name}' on '#{current_doc.document_id}'")
              current_doc.add_dev_error(name, e)
            ensure
              Logging.clear_details
            end
          else
            # This could happen while actions are propagating through the system
            current_doc.add_ops_error(name, 'Undefined action')
            @backoff.interruptible_backoff { !@running }
          end

          if current_doc.dev_errors.any? || current_doc.ops_errors.any?
            collection_name = current_doc.published? ? Connection.documents(current_doc.type).name : Connection.documents.name
            action_success = false
          end

          action_success
        end #delete_if
        current_doc.raw = nil if current_doc.pending_actions.empty?
      end

      unless got_one
        @logger.debug 'No document found for processing.'
        report_status(nil, nil)
        @backoff.interruptible_backoff { !@running }
      end

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
          doc.raw = action_doc.raw
          doc.title = action_doc.title
          doc.copyright = action_doc.copyright
          doc.document_timestamp = action_doc.document_timestamp || timestamp
          doc.display = action_doc.display
          version = action_doc.version

          published_doc = doc.get_published_copy_read_only
          if published_doc

            # ARM-770: Armagh should reject old document on publish
            if published_doc.document_timestamp && published_doc.document_timestamp > doc.document_timestamp
              @logger.ops_error "Action '#{action.name}' attempted to replace an existing published document ID '#{doc.document_id}' and timestamp '#{published_doc.document_timestamp}' with an older document timestamp '#{doc.document_timestamp}'. Aborting."
              abort
            end

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
            @logger.dev_warn "Action #{action.name} changed a previously published version of #{doc.type} #{doc.document_id} from version #{published_doc.version} to a lower value of #{version}." if version && version <= published_doc.version
            version ||= published_doc.version
          end

          doc.title = "#{doc.document_id} (unknown title)" if doc.title.nil? || doc.title.empty?
          doc.published_timestamp = timestamp
          doc.version = version || 1
          doc.state = action.config.output.docspec.state unless doc.error
          doc.add_items_to_pending_actions(@workflow_set.actions_names_handling_docspec(Documents::DocSpec.new(doc.type, doc.state)))
          doc.mark_publish
        when Actions::Consume
          @collection_task_ids = doc.collection_task_ids
          @archive_files = doc.archive_files
          published_doc = doc.to_published_document
          action.consume published_doc
          # Only metadata can be changed
          doc.metadata = published_doc.metadata

        when Actions::UtilityAction
          action.run
          doc.mark_delete

        when Actions::Action
          @logger.dev_error "#{action.name} is an unknown action type."
        else
          @logger.dev_error "#{action} is not an action."
      end
      raise Documents::Errors::IDError, "Attempted to change Document's ID from '#{initial_id}' to '#{doc.document_id}'.  IDs can only be changed from a publisher." unless initial_id == doc.document_id || allowed_id_change
    ensure
      @num_creates = 0
      @archives_for_collect.clear
    end

    def with_locked_action_state( action_name, **locking_args, &block )

      state_doc = ActionStateDocument.find_or_create_one_by_action_name_locked( action_name, self, **locking_args )
      if state_doc
        begin
          state_doc.content ||= {}
          yield state_doc.content
        ensure
          state_doc.save( true, self )
        end
      end
    end

    private def report_status(doc, action)
      now = Time.now

      if doc && action
        status = Status::RUNNING
        running_since = now
        task = {
          'document' => doc.document_id,
          'action' => action.name
        }
        @idle_since = nil
      else
        status = Status::IDLE
        @idle_since ||= now
        running_since = nil
        task = nil
      end

      @logger.debug "Reporting Status #{status['status']}"
      Status::AgentStatus.report(signature: @signature, hostname: @hostname, status: status, task: task, running_since: running_since, idle_since: @idle_since)
    end

    private def remove_status
      @logger.debug "Removing Status Report"
      Status::AgentStatus.delete(@signature)
    end
  end
end
