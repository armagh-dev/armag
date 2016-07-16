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

require_relative '../utils/exception_helper'
require_relative '../utils/processing_backoff'
require_relative '../connection'

require 'armagh/documents'

module Armagh
  class Document

    attr_accessor :published_id

    class << self
      protected :new
    end

    def self.version
      @version ||= {}
    end

    def self.create(type:,
        draft_content:,
        published_content:,
        draft_metadata:,
        published_metadata:,
        pending_actions:,
        state:,
        document_id:,
        title: nil,
        copyright: nil,
        source: nil,
        collection_task_ids:,
        document_timestamp:,
        new: false)
      doc = Document.new
      doc.type = type
      doc.draft_content = draft_content
      doc.published_content = published_content
      doc.draft_metadata = draft_metadata
      doc.published_metadata = published_metadata
      doc.document_id = document_id
      doc.add_pending_actions pending_actions
      doc.state = state
      doc.title = title if title
      doc.copyright = copyright if copyright
      doc.source = source if source
      doc.collection_task_ids = collection_task_ids if collection_task_ids
      doc.document_timestamp = document_timestamp if document_timestamp
      doc.save(new)
      doc
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
      rescue Mongo::Error::OperationFailure => e
        if e.message =~ /^E11000/
          # The document already exists.  It's already locked
          throw :already_locked, true
        else
          raise e
        end
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

    def self.find(document_id, type, state)
      db_doc = collection(type, state).find('document_id' => document_id).limit(1).first
      db_doc ? Document.new(db_doc) : nil
    end

    def self.get_for_processing
      # TODO Document.get_for_processing: Ability to pull multiple documents
      Connection.all_document_collections.each do |collection|
        db_doc = collection.find_one_and_update({'pending_work' => true, 'locked' => false}, {'$set' => {'locked' => true}}, {return_document: :after, sort: {'updated_timestamp' => 1}})
        return Document.new(db_doc) if db_doc
      end

      nil
    end

    def self.exists?(document_id, type, state)
      collection(type, state).find({'document_id' => document_id}).limit(1).count != 0
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

      doc.finish_processing if doc.is_a? Document
      nil
    end

    def self.delete(document_id, type, state)
      collection(type, state).delete_one({ 'document_id': document_id})
    end

    def self.unlock(document_id, type, state)
      collection(type, state).find_one_and_update({ 'document_id': document_id}, {'$set' => {'locked' => false}})
    end
    
    def self.collection(type = nil, state = nil)
      type_collection = (state == Documents::DocState::PUBLISHED) ? type : nil
      Connection.documents(type_collection)
    end

    def initialize(image = {})
      @pending_delete = false
      @pending_publish = false
      @pending_archive = false

      @db_doc = {
          'draft_metadata' => {},
          'published_metadata' => {},
          'draft_content' => {},
          'published_content' => nil,
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
          'source' => {},
          'document_timestamp' => nil}
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

    def locked?
      @db_doc['locked']
    end

    def published_content=(content)
      @db_doc['published_content'] = content
    end

    def published_content
      @db_doc['published_content']
    end

    def draft_content=(content)
      @db_doc['draft_content'] = content
    end

    def draft_content
      @db_doc['draft_content']
    end

    def draft_metadata
      @db_doc['draft_metadata']
    end

    def draft_metadata=(meta)
      @db_doc['draft_metadata'] = meta
    end

    def published_metadata
      @db_doc['published_metadata']
    end

    def published_metadata=(meta)
      @db_doc['published_metadata'] = meta
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
      dev_errors.merge(ops_errors){|_key, left, right| left + right}
    end

    def error?
      @db_doc['error'] ? true : false
    end

    def pending_work?
      @db_doc['pending_work'] ? true : false
    end

    def finish_processing
      @db_doc['locked'] = false
      update_pending_work
      save
    end

    # TODO Document#save - Buffered writing
    def save(new = false)
      now = Time.now
      @db_doc['created_timestamp'] ||= now
      @db_doc['updated_timestamp'] = now
      @db_doc['version'] = self.class.version
      @db_doc['collection_task_ids'].uniq!

      delete_orig = false

      if error? && state != Documents::DocState::PUBLISHED
        save_collection = Connection.failures
        delete_orig = true
      elsif @pending_publish
        save_collection = Connection.documents(type)
        delete_orig = true
      elsif @pending_archive
        save_collection = Connection.archive
        @pending_archive = false
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

      Connection.documents.delete_one({ '_id': internal_id}) if delete_orig

      @pending_publish = false
      @published_id = nil
    rescue Mongo::Error::MaxBSONSize
      raise Documents::Errors::DocumentSizeError.new("Document #{document_id} is too large.  Consider using a divider or splitter to break up the document.")
    rescue Mongo::Error::OperationFailure => e
      if e.message =~ /^E11000/
        raise Documents::Errors::DocumentUniquenessError.new("Unable to create document #{document_id}.  This document already exists.")
      else
        raise e
      end
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

    def to_draft_action_document
      docspec = Documents::DocSpec.new(type, state)
      Documents::ActionDocument.new(document_id: document_id,
                                    title: title,
                                    copyright: copyright,
                                    content: draft_content,
                                    metadata: draft_metadata,
                                    docspec: docspec,
                                    source: source,
                                    document_timestamp: document_timestamp)
    end

    def to_published_action_document
      docspec = Documents::DocSpec.new(type, state)
      Documents::ActionDocument.new(document_id: document_id,
                                    title: title,
                                    copyright: copyright,
                                    content: published_content,
                                    metadata: published_metadata,
                                    docspec: docspec,
                                    source: source,
                                    document_timestamp: document_timestamp)
    end

    def update_from_draft_action_document(action_doc)
      self.document_id = action_doc.document_id
      self.draft_content = action_doc.content
      self.published_content = {}
      self.draft_metadata = action_doc.metadata
      self.published_metadata = {}
      self.source = action_doc.source
      self.title = action_doc.title
      self.copyright = action_doc.copyright
      self.document_timestamp = action_doc.document_timestamp
      docspec = action_doc.docspec
      self.type = docspec.type
      self.state = docspec.state
      self
    end

    def mark_delete
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or publish.' if @pending_archive || @pending_publish
      @pending_delete = true
    end

    def mark_publish
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or delete.' if @pending_archive || @pending_delete
      @pending_publish = true
    end

    def mark_archive
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for delete or publish.' if @pending_delete || @pending_publish
      @pending_archive = true
    end

    private def update_pending_work
      if errors.any?
        @db_doc['error'] =  true
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
