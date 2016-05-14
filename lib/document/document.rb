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
require 'armagh/action_errors'

module Armagh
  class Document

    class << self
      protected :new
    end

    def self.version
      @version ||= {}
    end

    def self.create(type, draft_content, published_content, meta, pending_actions, state, id = nil, new = false)
      doc = Document.new
      doc.type = type
      doc.draft_content = draft_content
      doc.published_content = published_content
      doc.meta = meta
      doc.id = id if id
      doc.add_pending_actions pending_actions
      doc.state = state
      doc.save(id.nil? || new)
      doc
    end

    def self.from_action_document(action_doc, pending_actions = [])
      doc = Document.new
      doc.update_from_action_document(action_doc)
      doc.add_pending_actions pending_actions
      doc
    end

    # Returns document if found, nil if it didn't exist, throws :already_locked when doc exists but locked already
    def self.find_or_create_and_lock(id, type, state)
      begin
        db_doc = collection(type, state).find_one_and_update({'_id' => id, 'locked' => false}, {'$set' => {'locked' => true}}, {return_document: :before, upsert: true})
      rescue Mongo::Error::OperationFailure => e
        if e.message =~ /^E11000/
          # The document already exists.  It's already locked
          throw :already_locked, true
        else
          raise e
        end
      end

      if db_doc
        db_doc['locked'] = true
        doc = Document.new(db_doc)
      else
        # The document doesn't exist
        doc = nil
      end

      doc
    end

    def self.find(id, type, state)
      db_doc = collection(type, state).find('_id' => id).limit(1).first
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

    def self.exists?(id, type, state)
      collection(type, state).find({'_id' => id}).limit(1).count != 0
    end

    # Blocking Modify/Create.  If a doc with the id exists but is locked, wait until it's unlocked.
    def self.modify_or_create(id, type, state, running, logger = nil)
      raise LocalJumpError.new 'No block given' unless block_given?

      backoff = Utils::ProcessingBackoff.new
      backoff.logger = logger
      doc = nil

      until doc
        already_locked = catch(:already_locked) do
          doc = find_or_create_and_lock(id, type, state)
        end

        if doc.nil?
          if already_locked
            logger.info "Document '#{id}' already locked for editing.  Backing off." if logger
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
        # TODO JBOWES DONT APPLY CHANGES FROM YIELD
        if doc
          # Unlock only
          unlock(id, type, state)
        else
          delete(id, type, state)
        end

        raise e
      end
      doc.finish_processing if doc

      nil
    end

    def self.delete(id, type, state)
      collection(type, state).delete_one({ '_id': id})
    end

    def self.unlock(id, type, state)
      collection(type, state).find_one_and_update({ '_id': id}, {'$set' => {'locked' => false}})
    end
    
    def self.collection(type = nil, state = nil)
      type_collection = (state == DocState::PUBLISHED) ? type : nil
      Connection.documents(type_collection)
    end

    def initialize(image = {})
      @pending_delete = false
      @pending_publish = false
      @pending_archive = false

      @db_doc = {'meta' => {}, 'draft_content' => {}, 'published_content' => nil, 'type' => nil, 'locked' => false, 'pending_actions' => [], 'failed_actions' => {}, 'created_timestamp' => nil, 'updated_timestamp' => nil}
      @db_doc.merge! image
    end

    def id
      @db_doc['_id']
    end

    def id=(id)
      @db_doc['_id'] = id
    end

    def locked?
      @db_doc['locked']
    end

    def published_content=(published_content)
      @db_doc['published_content'] = published_content
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

    def meta
      @db_doc['meta']
    end

    def meta=(meta)
      @db_doc['meta'] = meta
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

    def add_failed_action(action, details)
      if details.is_a? Exception
        @db_doc['failed_actions'][action] = Utils::ExceptionHelper.exception_to_hash details
      else
        @db_doc['failed_actions'][action] = {'message' => details.to_s}
      end
      update_pending_work
    end

    def remove_failed_action(action)
      @db_doc['failed_actions'].delete(action)
      update_pending_work
    end

    def clear_failed_actions
      @db_doc['failed_actions'].clear
      update_pending_work
    end

    def failed_actions
      @db_doc['failed_actions']
    end

    def failed?
      @db_doc['failure'] ? true : false
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

      delete_orig = false

      if failed? && state != DocState::PUBLISHED
        save_collection = Connection.failures
        delete_orig = true
      elsif @pending_publish
        save_collection = Connection.documents(type)
        @pending_publish = false
        delete_orig = true
      elsif @pending_archive
        save_collection = Connection.archive
        @pending_archive = false
        delete_orig = true
      elsif @pending_delete
        @pending_delete = false
        delete_orig = true
        save_collection = nil
      elsif state == DocState::PUBLISHED
        save_collection = Connection.documents(type)
      else
        save_collection = Connection.documents
      end

      if save_collection
        if new
          @db_doc['_id'] = save_collection.insert_one(@db_doc).inserted_ids.first
        else
          save_collection.replace_one({'_id': id}, @db_doc, {upsert: true})
        end
      end

      Connection.documents.delete_one({ '_id': id}) if delete_orig

    rescue Mongo::Error::MaxBSONSize
      raise ActionErrors::DocumentSizeError.new("Document #{id} is too large.  Consider using a splitter or parser to split the document.")
    rescue Mongo::Error::OperationFailure => e
      if e.message =~ /^E11000/
        raise ActionErrors::DocumentUniquenessError.new("Unable to create document #{id}.  This document already exists.")
      else
        raise e
      end
    end

    def state
      @db_doc['state']
    end

    def state=(state)
      if DocState.valid_state?(state)
        @db_doc['state'] = state
      else
        raise ActionErrors::StateError.new "Tried to set state to an unknown state: '#{state}'."
      end
    end

    def ready?
      state == DocState::READY
    end

    def working?
      state == DocState::WORKING
    end

    def published?
      state == DocState::PUBLISHED
    end

    def to_action_document
      docspec = DocSpec.new(type, state)
      ActionDocument.new(id, draft_content, published_content, meta, docspec)
    end

    def to_publish_action_document
      docspec = DocSpec.new(type, state)
      published_doc = self.class.find(id, type, DocState::PUBLISHED)
      if published_doc
        pub_content = published_doc.published_content
      else
        pub_content = published_content
      end
      ActionDocument.new(id, draft_content, pub_content, meta, docspec)
    end

    def update_from_action_document(action_doc)
      self.id = action_doc.id
      self.draft_content = action_doc.draft_content
      self.published_content = action_doc.published_content
      self.meta = action_doc.meta
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
      if @db_doc['failed_actions'].any?
        @db_doc['failure'] =  true
      else
        @db_doc.delete 'failure'
      end

      if @db_doc['pending_actions'].any? && !@db_doc['failure']
        @db_doc['pending_work'] = true
      else
        @db_doc.delete 'pending_work'
      end
    end
  end
end
