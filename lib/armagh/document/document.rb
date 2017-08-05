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

require_relative '../utils/db_doc_helper'
require_relative '../utils/exception_helper'
require_relative '../utils/processing_backoff'
require_relative '../connection'

require 'armagh/documents'
require 'armagh/support/encoding'
require 'armagh/support/random'

require 'bson'

module Armagh
  class Document < Connection::DBDoc
    class DocumentMarkError < StandardError;
    end

    def self.default_collection
      Connection.documents
    end

    def self.version
      @version ||= {}
    end

    attr_accessor :published_id
    delegated_attr_accessor       :document_id
    delegated_attr_accessor       :version
    delegated_attr_accessor       :title
    delegated_attr_accessor       :copyright
    delegated_attr_accessor       :published_timestamp, after_return: :get_ts_utc
    delegated_attr_accessor_array :collection_task_ids
    delegated_attr_accessor       :source
    delegated_attr_accessor       :document_timestamp,  after_return: :get_ts_utc
    delegated_attr_accessor       :display
    delegated_attr_accessor       :content
    delegated_attr_accessor       :metadata
    delegated_attr_accessor       :type
    delegated_attr_accessor_array :archive_files
    delegated_attr_accessor       :raw,                 validates_with: :validate_raw,  after_return: :get_raw_data
    delegated_attr_accessor       :state,               validates_with: :validate_state
    delegated_attr_accessor_array :pending_actions,     after_change: :update_pending_work
    delegated_attr_accessor       :error
    delegated_attr_accessor_errors :dev_errors,         after_change: :update_pending_work
    delegated_attr_accessor_errors :ops_errors,         after_change: :update_pending_work
    delegated_attr_accessor       :pending_work

    alias_method :add_dev_error, :add_error_to_dev_errors
    alias_method :remove_dev_error, :remove_error_from_dev_errors
    alias_method :add_ops_error, :add_error_to_ops_errors
    alias_method :remove_ops_error, :remove_error_from_ops_errors

    def validate_raw(raw)
      if raw.is_a?(String)
        BSON::Binary.new(raw)
      elsif raw.nil?
        nil
      elsif raw.is_a?(BSON::Binary)
        raw
      else
        raise TypeError, 'Value for raw expected to be a string.'
      end
    end

    def get_raw_data(raw)
      raw&.data
    end

    def validate_state(state)
      if Documents::DocState.valid_state?(state)
        state
      else
        raise Documents::Errors::DocStateError.new "Tried to set state to an unknown state: '#{state}'."
      end
    end

    def self.create(type:,
      content:,
      raw:,
      metadata:,
      pending_actions:,
      state:,
      document_id:,
      title: nil,
      copyright: nil,
      source: nil,
      collection_task_ids:,
      archive_files: [],
      document_timestamp:,
      display: nil,
      new: false,
      version: {},
      logger: nil)
      doc = Document.new
      doc.type = type
      doc.content = content
      doc.raw = raw
      doc.metadata = metadata
      doc.document_id = document_id
      doc.add_items_to_pending_actions pending_actions
      doc.state = state
      doc.title = title if title
      doc.copyright = copyright if copyright
      doc.source = source.to_hash if source
      doc.add_items_to_collection_task_ids collection_task_ids
      doc.add_items_to_archive_files archive_files
      doc.document_timestamp = document_timestamp if document_timestamp
      doc.display = display if display
      doc.version = version
      doc.save(new: new, logger: logger)
      doc
    end

    def self.create_trigger_document(state:, type:, pending_actions:)
      now = Time.now
      doc = Document.new
      doc.document_id = Armagh::Support::Random.random_id
      doc.type = type
      doc.state = state
      doc.add_items_to_pending_actions pending_actions
      doc.metadata = {}
      doc.content = {}
      doc.raw = nil 
      doc.created_timestamp = now
      doc.updated_timestamp = now


      # Not using create because we want to not allow an insertion if one already exists
      db_update({'type' => type, 'state' => state}, doc.db_doc)
    rescue => e
      raise Connection.convert_mongo_exception(e, id: doc.document_id, type_class: self)
    end

    def self.from_action_document(action_doc, pending_actions = [])
      doc = Document.new
      doc.update_from_draft_action_document(action_doc)
      doc.add_items_to_pending_actions pending_actions
      doc
    end

    # Returns document if found, internal_id if it didn't exist, throws :already_locked when doc exists but locked already
    def self.find_or_create_and_lock(document_id, type, state, agent_id)
      begin
        db_doc = db_find_and_update({'document_id' => document_id, 'locked' => false, 'type' => type}, {'locked' => true}, collection(type, state))
      rescue => e
        e = Connection.convert_mongo_exception(e, id: document_id, type_class: self)
        throw(:already_locked, true) if e.is_a? Connection::DocumentUniquenessError
        raise e
      end

      if db_doc['pending_actions']
        db_doc['locked'] = agent_id
        doc = Document.new(db_doc)
      else
        # The document doesn't exist
        doc = db_doc['_id']
      end

      doc
    end

    def self.count_incomplete_by_doctype( pub_type_names = nil )
      pub_types = pub_type_names ?
          pub_type_names.collect{ |pt| Connection.documents(pt) } :
          Connection.all_document_collections.select{ |c| Connection.published_collection?(c) }
      counts = {}
      queries = [
          { doc_colls: [ Connection.documents ], filter: nil },
          { doc_colls: [ Connection.failures ],  filter: nil },  #TODO filter out acknowledged failures
          { doc_colls: pub_types, filter: { 'pending_work' => true }}
      ]

      group_by_doctype_clause = {'$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}
      queries.each do |query_params|
        query_params[:doc_colls].each do |doc_coll|
          counts[ doc_coll.name ] = {}
          match_clause = query_params[:filter] ? { '$match' => query_params[:filter] } : nil
          pipeline = [ match_clause, group_by_doctype_clause ].compact
          counts_by_type_in_coll = doc_coll.aggregate( pipeline ).to_a
          counts_by_type_in_coll.each do |count_detail|
            docspec_brief = "#{count_detail['_id']['type']}:#{count_detail['_id']['state']}"
            counts[doc_coll.name][docspec_brief] = count_detail['count']
          end
        end
      end
      counts
    end

    def self.find_documents(doc_type, begin_ts, end_ts, start_index, max_returns)
      options = {}
      ts_options = {}
      ts_options['$gte'] = begin_ts if begin_ts
      ts_options['$lte'] = end_ts if end_ts
      options['document_timestamp'] = ts_options unless ts_options.empty?

      skip = start_index || 0
      limit = max_returns || 20

      db_find(options, collection(doc_type, Documents::DocState::PUBLISHED)).sort('document_timestamp' => -1).skip(skip).limit(limit)
    end

    def self.find(document_id, type, state, raw: false)
      db_doc = db_find_one({'document_id' => document_id, 'type' => type}, collection(type, state))
      if raw
        Utils::DBDocHelper.restore_model(db_doc, raw: true)
        return db_doc
      else
        db_doc ? Document.new(db_doc) : nil
      end
    rescue => e
      raise Connection.convert_mongo_exception(e, id: document_id, type_class: self)
    end

    def self.failures(raw: false)
      if raw
        documents = Connection.failures.find.to_a
        documents.each{|d| Utils::DBDocHelper.restore_model(d, raw: true)}
      else
        documents = []
        Connection.failures.find.each do |db_doc|
          documents << Document.new(db_doc)
        end
      end

      documents
    end

    def self.get_for_processing(agent_id)
      Connection.all_document_collections.each do |collection|
        db_doc = collection.find_one_and_update({'pending_work' => true, 'locked' => false}, {'$set' => {'locked' => agent_id}}, {return_document: :after, sort: {'updated_timestamp' => 1}})

        return Document.new(db_doc) if db_doc
      end

      nil
    rescue => e
      raise Connection.convert_mongo_exception(e)
    end

    def self.exists?(document_id, type, state)
      db_find_one({'document_id' => document_id, 'type' => type}, collection(type, state)) != nil
    rescue => e
      raise Connection.convert_mongo_exception(e, id: document_id, type_class: self)
    end

    # Blocking Modify/Create.  If a doc with the id exists but is locked, wait until it's unlocked.
    def self.modify_or_create(document_id, type, state, running, agent_id, logger = nil)
      raise LocalJumpError.new 'No block given' unless block_given?

      backoff = Utils::ProcessingBackoff.new
      backoff.logger = logger
      doc = nil

      until doc
        already_locked = catch(:already_locked) do
          doc = find_or_create_and_lock(document_id, type, state, agent_id)
          false
        end

        unless doc.is_a? Document
          if already_locked
            logger.info "Document '#{document_id}' already locked for editing.  Backing off." if logger
            backoff.interruptible_backoff {!running}
          else
            # The document doesn't even exist - dont keep trying
            break
          end
        end
      end

      begin
        yield doc
      rescue => e
        if doc.is_a? Document
          unlock(document_id, type, state) # Unlock - don't apply changes
        else
          delete(document_id, type, state) # This was a new document.  Delete the locked placeholder.
        end
        raise e
      end

      doc.finish_processing(logger) if doc.is_a? Document
      nil
    end

    def self.delete(document_id, type, state)
      db_delete({'document_id': document_id}, collection(type, state))
    rescue => e
      raise Connection.convert_mongo_exception(e, id: document_id, type_class: self)
    end

    def self.unlock(document_id, type, state)
      db_find_and_update({'document_id': document_id, 'type' => type}, {'locked' => false}, collection(type, state))
    rescue => e
      raise Connection.convert_mongo_exception(e, id: document_id, type_class: self)
    end

    def self.force_unlock(agent_id)
      Connection.all_document_collections.each do |collection|
        collection.update_many({'locked' => agent_id}, {'$set' => {'locked' => false}})
      end
    rescue => e
      raise Connection.convert_mongo_exception(e)
    end

    def self.collection(type = nil, state = nil)
      type_collection = (state == Documents::DocState::PUBLISHED) ? type : nil
      Connection.documents(type_collection)
    end

    def initialize(image = {})
      @pending_delete = false
      @pending_publish = false
      @pending_collection_history = false
      @abort = false

      h = {
        'metadata' => {},
        'content' => {},
        'raw' => nil,
        'type' => nil,
        'locked' => false,
        'pending_actions' => [],
        'dev_errors' => {},
        'ops_errors' => {},
        'created_timestamp' => nil,
        'updated_timestamp' => nil,
        'title' => nil,
        'copyright' => nil,
        'published_timestamp' => nil,
        'collection_task_ids' => [],
        'archive_files' => [],
        'source' => {},
        'document_timestamp' => nil,
        'version' => {},
        'display' => nil
      }
      h.merge! image

      super(h)
    end


    def locked?
      # only return true or false
      @db_doc['locked'] != false
    end

    def locked_by
      @db_doc['locked'] || nil
    end

    def clear_errors
      clear_dev_errors
      clear_ops_errors
    end

    def errors
      dev_errors.merge(ops_errors) {|_key, left, right| left + right}
    end

    def error?
      dev_errors.any? || ops_errors.any?
    end

    def pending_work?
      pending_work ? true : false
    end

    def finish_processing(logger)
      @db_doc['locked'] = false
      update_pending_work
      save(logger: logger)
    end

    def save(new: false, logger: nil)
      self.mark_timestamp
      self.version = self.class.version
      self.collection_task_ids.uniq!
      self.archive_files.uniq!

      if error?
        self.error = true
      else
        delete_error
      end

      fix_encoding( source['encoding'], logger: logger)
      clean_model

      delete_orig = false

      if @abort && !published?
        delete_orig = true
        save_collection = nil
      elsif error? && !published?
        save_collection = Connection.failures
        delete_orig = true
      elsif @pending_publish
        save_collection = Connection.documents(type)
        delete_orig = true
      elsif @pending_collection_history
        save_collection = Connection.collection_history
        delete_orig = true
      elsif @pending_delete
        delete_orig = true
        save_collection = nil
      elsif published?
        save_collection = Connection.documents(type)
      else
        save_collection = Connection.documents
      end

      if save_collection
        if new || self.internal_id.nil?
          self.internal_id = self.class.db_create(@db_doc, save_collection)
        else
          if @pending_publish && @published_id
            self.class.db_replace({'document_id': document_id}, @db_doc.merge({'_id' => @published_id}), save_collection)
          else
            self.class.db_replace({'_id': self.internal_id}, @db_doc, save_collection)
          end
        end
      end

      self.class.db_delete({'_id': self.internal_id}) if delete_orig

      clear_marks
      @published_id = nil
    rescue => e
      raise Connection.convert_mongo_exception(e, id: document_id, type_class: self.class)
    end

    def ready?
      state == Documents::DocState::READY
    end

    def working?
      state == Documents::DocState::WORKING
    end

    def published?
      state == Documents::DocState::PUBLISHED
    end

    def get_published_copy
      self.class.find(document_id, type, Documents::DocState::PUBLISHED)
    end

    def to_action_document
      docspec = Documents::DocSpec.new(type, state)
      Documents::ActionDocument.new(document_id: document_id.deep_copy,
                                    title: title.deep_copy,
                                    copyright: copyright.deep_copy,
                                    content: content.deep_copy,
                                    raw: raw.deep_copy,
                                    metadata: metadata.deep_copy,
                                    docspec: docspec,
                                    source: Armagh::Documents::Source.from_hash(source.deep_copy),
                                    document_timestamp: document_timestamp,
                                    display: display.deep_copy)
    end

    def to_published_document
      docspec = Documents::DocSpec.new(type, state)
      Documents::PublishedDocument.new(document_id: document_id.deep_copy,
                                       title: title.deep_copy,
                                       copyright: copyright.deep_copy,
                                       content: content.deep_copy,
                                       raw: raw.deep_copy,
                                       metadata: metadata.deep_copy,
                                       docspec: docspec.deep_copy,
                                       source: Armagh::Documents::Source.from_hash(source.deep_copy),
                                       document_timestamp: document_timestamp,
                                       display: display.deep_copy)

    end

    def update_from_draft_action_document(action_doc)
      self.document_id = action_doc.document_id
      self.content = action_doc.content
      self.raw = action_doc.raw
      self.metadata = action_doc.metadata
      self.source = action_doc.source.to_hash
      self.title = action_doc.title
      self.copyright = action_doc.copyright
      self.document_timestamp = action_doc.document_timestamp
      self.display = action_doc.display
      docspec = action_doc.docspec
      self.type = docspec.type
      self.state = docspec.state
      self
    end

    def mark_delete
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or publish.' if @pending_collection_history || @pending_publish
      @pending_delete = true
    end

    def mark_publish
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or delete.' if @pending_collection_history || @pending_delete
      @pending_publish = true
    end

    def mark_collection_history
      raise DocumentMarkError, 'Document cannot be marked to save collection history.  It is already marked for delete or publish.' if @pending_delete || @pending_publish
      @pending_collection_history = true
    end

    def mark_abort
      clear_marks
      @abort = true
    end

    def clear_marks
      @pending_delete = false
      @pending_publish = false
      @pending_collection_history = false
      @abort = false
    end

    private def update_pending_work( _pending_actions=nil)
      if pending_actions.any? && !error?
        self.pending_work = true
      else
        delete_pending_work
      end
      pending_actions
    end
  end
end
