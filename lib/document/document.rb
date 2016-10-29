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

require 'armagh/support/encoding'

require_relative '../../lib/utils/document_helper'
require_relative '../utils/exception_helper'
require_relative '../utils/processing_backoff'
require_relative '../connection'

require 'armagh/documents'
require 'securerandom'

module Armagh
  class Document

    attr_accessor :published_id
    attr_reader :db_doc

    class << self
      protected :new
    end

    def self.version
      @version ||= {}
    end

    def self.create(type:,
        content:,
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
        logger: nil)
      doc = Document.new
      doc.type = type
      doc.content = content
      doc.metadata = metadata
      doc.document_id = document_id
      doc.add_pending_actions pending_actions
      doc.state = state
      doc.title = title if title
      doc.copyright = copyright if copyright
      doc.source = source.to_hash if source
      doc.collection_task_ids = collection_task_ids
      doc.archive_files = archive_files
      doc.document_timestamp = document_timestamp if document_timestamp
      doc.display = display if display
      doc.save(new: new, logger: logger)
      doc
    end

    def self.create_trigger_document(state:, type:, pending_actions:)
      doc = Document.new
      doc.document_id = SecureRandom.uuid
      doc.type = type
      doc.state = state
      doc.add_pending_actions pending_actions
      doc.metadata = {}
      doc.content = {}
      doc.created_timestamp = Time.now

      Connection.documents.update_one(
        {'type' => type, 'state' => state},
        {'$setOnInsert': doc.db_doc},
        {upsert: true}
      )
    rescue => e
      raise Connection.convert_mongo_exception(e, doc.document_id)
    end

    def self.from_action_document(action_doc, pending_actions = [])
      doc = Document.new
      doc.update_from_draft_action_document(action_doc)
      doc.add_pending_actions pending_actions
      doc
    end

    # Returns document if found, internal_id if it didn't exist, throws :already_locked when doc exists but locked already
    def self.find_or_create_and_lock(document_id, type, state)
      begin
        db_doc = collection(type, state).find_one_and_update({'document_id' => document_id, 'locked' => false}, {'$set' => {'locked' => true}}, {return_document: :after, upsert: true})
      rescue => e
        e = Connection.convert_mongo_exception(e, document_id)
        throw(:already_locked, true) if e.is_a? Documents::Errors::DocumentUniquenessError
        raise e
      end

      if db_doc['type']
        db_doc['locked'] = true
        doc = Document.new(db_doc)
      else
        # The document doesn't exist
        doc = db_doc['_id']
      end

      doc
    end


    def self.count_working_by_doctype
      counts = {}
      Connection.all_document_collections.each do |doc_coll|
        counts[doc_coll.name] = {}
        doc_coll.aggregate([
                             {'$group' => {'_id' => {'type' => '$type', 'state' => '$state'},
                                           'count' => {'$sum' => 1}}}
                           ]).to_a.each do |h|
          docspec_brief = "#{h['_id']['type']}:#{h['_id']['state']}"
          counts[doc_coll.name][docspec_brief] = h['count']
        end
      end
      counts
    end

    def self.find_documents( doc_type, begin_ts, end_ts, start_index, max_returns )
      
      options = {}
      ts_options = {}
      ts_options[ '$gte' ] = begin_ts if begin_ts
      ts_options[ '$lte' ] = end_ts if end_ts
      options[ 'document_timestamp' ] = ts_options unless ts_options.empty?
      
      skip = start_index || 0
      limit = max_returns || 20
      
      collection( doc_type, 'published' ).find( options ).projection( { '_id' => 0, 'document_id' => 1, 'type' => 1, 'title' => 1, 'document_timestamp' => 1 } ).sort( 'document_timestamp' => -1 ).skip( skip ).limit( limit )
    end

    def self.find(document_id, type, state, raw: false)
      db_doc = collection(type, state).find('document_id' => document_id).limit(1).first
      if raw
        return db_doc
      else
        db_doc ? Document.new(db_doc) : nil
      end
    rescue => e
      raise Connection.convert_mongo_exception(e, document_id)
    end

    def self.get_for_processing
      Connection.all_document_collections.each do |collection|
        db_doc = collection.find_one_and_update({'pending_work' => true, 'locked' => false}, {'$set' => {'locked' => true}}, {return_document: :after, sort: {'updated_timestamp' => 1}})
        return Document.new(db_doc) if db_doc
      end

      nil
    rescue => e
      raise Connection.convert_mongo_exception(e)
    end

    def self.exists?(document_id, type, state)
      collection(type, state).find({'document_id' => document_id}).limit(1).count != 0
    rescue => e
      raise Connection.convert_mongo_exception(e, document_id)
    end

    # Blocking Modify/Create.  If a doc with the id exists but is locked, wait until it's unlocked.
    def self.modify_or_create(document_id, type, state, running, logger = nil)
      raise LocalJumpError.new 'No block given' unless block_given?

      backoff = Utils::ProcessingBackoff.new
      backoff.logger = logger
      doc = nil

      until doc
        already_locked = catch(:already_locked) do
          doc = find_or_create_and_lock(document_id, type, state)
          false
        end

        unless doc.is_a? Document
          if already_locked
            logger.info "Document '#{document_id}' already locked for editing.  Backing off." if logger
            backoff.interruptible_backoff { !running }
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
      collection(type, state).delete_one({'document_id': document_id})
    rescue => e
      raise Connection.convert_mongo_exception(e, document_id)
    end

    def self.unlock(document_id, type, state)
      collection(type, state).find_one_and_update({'document_id': document_id}, {'$set' => {'locked' => false}})
    rescue => e
      raise Connection.convert_mongo_exception(e, document_id)
    end

    def self.collection(type = nil, state = nil)
      type_collection = (state == Documents::DocState::PUBLISHED) ? type : nil
      Connection.documents(type_collection)
    end

    def initialize(image = {})
      @pending_delete = false
      @pending_publish = false
      @pending_collection_history = false

      @db_doc = {
          'metadata' => {},
          'content' => {},
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
          'display' => nil
      }
      @db_doc.merge! image
    end

    def internal_id
      @db_doc['_id']
    end

    def internal_id=(id)
      @db_doc['_id'] = id
    end

    def document_id
      @db_doc['document_id']
    end

    def document_id=(id)
      @db_doc['document_id'] = id
    end

    def title
      @db_doc['title']
    end

    def title=(title)
      @db_doc['title'] = title
    end

    def copyright
      @db_doc['copyright']
    end

    def copyright=(copyright)
      @db_doc['copyright'] = copyright
    end

    def published_timestamp
      @db_doc['published_timestamp']
    end

    def published_timestamp=(ts)
      @db_doc['published_timestamp'] = ts
    end

    def collection_task_ids
      @db_doc['collection_task_ids']
    end

    def collection_task_ids=(collection_task_ids)
      @db_doc['collection_task_ids'] = collection_task_ids
    end

    def source
      @db_doc['source']
    end

    def source=(source)
      @db_doc['source'] = source
    end

    def document_timestamp
      @db_doc['document_timestamp']
    end

    def document_timestamp=(document_timestamp)
      @db_doc['document_timestamp'] = document_timestamp
    end

    def display
      @db_doc['display']
    end

    def display=(display)
      @db_doc['display'] = display
    end

    def locked?
      @db_doc['locked']
    end

    def content=(content)
      @db_doc['content'] = content
    end

    def content
      @db_doc['content']
    end

    def metadata
      @db_doc['metadata']
    end

    def metadata=(meta)
      @db_doc['metadata'] = meta
    end

    def type=(type)
      @db_doc['type'] = type
    end

    def type
      @db_doc['type']
    end

    def updated_timestamp
      @db_doc['updated_timestamp']
    end

    def created_timestamp
      @db_doc['created_timestamp']
    end

    def created_timestamp=(ts)
      @db_doc['created_timestamp'] = ts
    end

    def version
      @db_doc['version']
    end

    def archive_files
      @db_doc['archive_files']
    end

    def archive_files=(archive_files)
      @db_doc['archive_files'] = archive_files
    end

    def pending_actions
      @db_doc['pending_actions']
    end

    def add_pending_actions(*actions)
      @db_doc['pending_actions'].concat(actions.flatten.compact)
      update_pending_work
    end

    def remove_pending_action(action)
      @db_doc['pending_actions'].delete(action)
      update_pending_work
    end

    def clear_pending_actions
      @db_doc['pending_actions'].clear
      update_pending_work
    end

    def add_dev_error(action_name, details)
      @db_doc['dev_errors'][action_name] ||= []

      if details.is_a? Exception
        @db_doc['dev_errors'][action_name] << Utils::ExceptionHelper.exception_to_hash(details)
      else
        @db_doc['dev_errors'][action_name] << {'message' => details.to_s}
      end
      update_pending_work
    end

    def remove_dev_error(action)
      @db_doc['dev_errors'].delete(action)
      update_pending_work
    end

    def clear_dev_errors
      @db_doc['dev_errors'].clear
      update_pending_work
    end

    def dev_errors
      @db_doc['dev_errors']
    end

    def add_ops_error(action_name, details)
      @db_doc['ops_errors'][action_name] ||= []
      if details.is_a? Exception
        @db_doc['ops_errors'][action_name] << Utils::ExceptionHelper.exception_to_hash(details)
      else
        @db_doc['ops_errors'][action_name] << {'message' => details.to_s}
      end
      update_pending_work
    end

    def remove_ops_error(action)
      @db_doc['ops_errors'].delete(action)
      update_pending_work
    end

    def clear_ops_errors
      @db_doc['ops_errors'].clear
      update_pending_work
    end

    def ops_errors
      @db_doc['ops_errors']
    end

    def clear_errors
      clear_dev_errors
      clear_ops_errors
    end

    def errors
      dev_errors.merge(ops_errors) { |_key, left, right| left + right }
    end

    def error?
      @db_doc['error'] ? true : false
    end

    def pending_work?
      @db_doc['pending_work'] ? true : false
    end

    def finish_processing(logger)
      @db_doc['locked'] = false
      update_pending_work
      save(logger: logger)
    end

    def save(new: false, logger: nil)
      now = Time.now
      @db_doc['created_timestamp'] ||= now
      @db_doc['updated_timestamp'] = now
      @db_doc['version'] = self.class.version
      @db_doc['collection_task_ids'].uniq!
      @db_doc['archive_files'].uniq!

      @db_doc = Armagh::Support::Encoding.fix_encoding(@db_doc, proposed_encoding: @db_doc['source']['encoding'], logger: logger)
      Armagh::Utils::DocumentHelper.clean_document(self)

      delete_orig = false

      if error? && state != Documents::DocState::PUBLISHED
        save_collection = Connection.failures
        delete_orig = true
      elsif @pending_publish
        save_collection = Connection.documents(type)
        delete_orig = true
      elsif @pending_collection_history
        save_collection = Connection.collection_history
        @pending_collection_history = false
        delete_orig = true
      elsif @pending_delete
        @pending_delete = false
        delete_orig = true
        save_collection = nil
      elsif state == Documents::DocState::PUBLISHED
        save_collection = Connection.documents(type)
      else
        save_collection = Connection.documents
      end

      if save_collection
        if new || internal_id.nil?
          @db_doc['_id'] = save_collection.insert_one(@db_doc).inserted_ids.first
        else
          if @pending_publish && @published_id
            save_collection.replace_one({'document_id': document_id}, @db_doc.merge({'_id' => @published_id}), {upsert: true})
          else
            save_collection.replace_one({'_id': internal_id}, @db_doc, {upsert: true})
          end
        end
      end

      Connection.documents.delete_one({'_id': internal_id}) if delete_orig

      @pending_publish = false
      @published_id = nil
    rescue => e
      raise Connection.convert_mongo_exception(e, document_id)
    end

    def state
      @db_doc['state']
    end

    def state=(state)
      if Documents::DocState.valid_state?(state)
        @db_doc['state'] = state
      else
        raise Documents::Errors::DocStateError.new "Tried to set state to an unknown state: '#{state}'."
      end
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
      Documents::ActionDocument.new(document_id: document_id,
                                    title: title,
                                    copyright: copyright,
                                    content: content,
                                    metadata: metadata,
                                    docspec: docspec,
                                    source: Armagh::Documents::Source.from_hash(source),
                                    document_timestamp: document_timestamp,
                                    display: display )
#                                    archive_file: archive_file)
    end

    def to_published_document
      docspec = Documents::DocSpec.new(type, state)
      Documents::PublishedDocument.new(document_id: document_id,
                                       title: title,
                                       copyright: copyright,
                                       content: content,
                                       metadata: metadata,
                                       docspec: docspec,
                                       source: Armagh::Documents::Source.from_hash(source),
                                       document_timestamp: document_timestamp,
                                       display: display )
#                                       archive_file: archive_file)

    end

    def update_from_draft_action_document(action_doc)
      self.document_id = action_doc.document_id
      self.content = action_doc.content
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

    private def update_pending_work
      if errors.any?
        @db_doc['error'] = true
      else
        @db_doc.delete 'error'
      end

      if @db_doc['pending_actions'].any? && !@db_doc['error']
        @db_doc['pending_work'] = true
      else
        @db_doc.delete 'pending_work'
      end
    end
  end
end
