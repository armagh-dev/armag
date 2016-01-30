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

require 'digest/md5'
require_relative '../utils/processing_backoff'
require_relative '../connection'

require 'armagh/doc_state'
require 'armagh/action_document'

module Armagh
  class Document

    def self.create(type, content, meta, pending_actions, doc_state, id=nil)
      doc = Document.new
      doc.type = type
      doc.content = content
      doc.meta = meta
      doc.id = id if id
      doc.add_pending_actions pending_actions
      doc.state = doc_state
      doc.save
      doc
    end

    def self.find_and_lock(id)
      # TODO Index on ID/locked
      db_doc = Connection.documents.find_one_and_update({'_id' => id, 'locked' => false}, {'$set' => {'locked' => true}}, :return_document => :after)
      db_doc ? Document.new(db_doc) : nil
    end

    def self.find(id)
      # TODO Index on ID
      db_doc = Connection.documents.find('_id' => id).limit(1).first
      db_doc ? Document.new(db_doc) : nil
    end

    def self.get_for_processing(num = 1)
      # TODO find a document in the following order
      #  Oldest -> Newest: No local agent picked up for too long
      #  Oldest -> Newest: local
      # TODO Doc must be in a valid state
      # TODO Ability to pull multiple documents
      # TODO Index on pending_work/locked/and state
      db_doc = Connection.documents.find_one_and_update({'pending_work' => true, 'locked' => false, 'state' => DocState::PUBLISHED}, {'$set' => {'locked' => true}}, :return_document => :after)
      db_doc ? Document.new(db_doc) : nil
    end

    def self.exists?(id)
      # TODO Index on ID
      Connection.documents.find({'_id' => id}).limit(1).count != 0
    end

    # Blocking Modify.  If a doc with the id exists but is locked, wait until it's unlocked.  Return true if a doc existed to be modified.  false otherwise
    def self.modify(id)
      raise LocalJumpError.new('no block given') unless block_given?
      doc_available = false

      backoff = Utils::ProcessingBackoff.new
      doc = nil

      until doc
        doc = find_and_lock(id)

        if doc.nil?
          if exists?(id)
            backoff.backoff
          else
            # The document doesn't even exist - dont keep trying
            break
          end
        end
      end

      if doc
        doc_available = true
        begin
          yield doc
        ensure
          doc.finish_processing
        end
      end

      return doc_available
    end

    # Non blocking modify.  If the id doesn't exist or is locked, the block is not yielded.  Return true if a doc existed and was not locked.  false otherwise
    def self.modify!(id)
      raise LocalJumpError.new('no block given') unless block_given?
      doc_available = false

      doc = find_and_lock(id)

      if doc
        doc_available = true
        begin
          yield doc
        ensure
          doc.finish_processing
        end
      end

      doc_available
    end

    protected def new(*args)
      super(args)
    end

    protected def initialize(image = {})
      @db_doc = {'meta' => {}, 'content' => nil, 'md5' => nil, 'type' => nil, 'pending_actions' => [], 'failed_actions' => {}, 'locked' => false, 'pending_work' => false, 'created_timestamp' => nil, 'updated_timestamp' => nil}
      @db_doc.merge! image
    end

    def id
      @db_doc['_id']
    end

    def id=(id)
      @db_doc['_id'] = id
    end

    def content=(content)
      @db_doc['content'] = content
      @db_doc['md5'] = content.nil? ? nil : Digest::MD5.hexdigest(content)
    end

    def content
      @db_doc['content']
    end

    def md5
      @db_doc['md5']
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

    def add_pending_actions(*actions)
      @db_doc['pending_actions'].concat(actions.flatten.compact)
      update_pending_work
    end

    def remove_pending_action(action)
      @db_doc['pending_actions'].delete(action)
      update_pending_work
    end

    def add_failed_action(action, details)
      if details.is_a? Exception
        @db_doc['failed_actions'][action] = {'message' => details.message, 'trace' => details.backtrace}
      else
        @db_doc['failed_actions'][action] = {'message' => details.to_s}
      end
    end

    def remove_failed_action(action)
      @db_doc['failed_actions'].delete(action)
    end

    def failed_actions
      @db_doc['failed_actions']
    end

    def pending_actions
      @db_doc['pending_actions']
    end

    def pending_work
      @db_doc['pending_work']
    end

    def finish_processing
      @db_doc['locked'] = false
      save
    end

    def save
      now = Time.now
      @db_doc['created_timestamp'] ||= now
      @db_doc['updated_timestamp'] = now

      if id
        Connection.documents.replace_one({ '_id': id}, @db_doc, {upsert: true})
      else
        @db_doc['_id'] = Connection.documents.insert_one(@db_doc).inserted_ids.first
      end
    end

    def state
      @db_doc['state']
    end

    def state=(state)
      if DocState.valid_state?(state)
        @db_doc['state'] = state
      else
        raise "Tried to set state to an unknown state: '#{state}'."
      end
    end

    def pending?
      state == DocState::PENDING
    end

    def published?
      state == DocState::PUBLISHED
    end

    def closed?
      state == DocState::CLOSED
    end

    def to_action_document
      ActionDocument.new(content.dup, meta, state)
    end

    def update_from_action_document(action_doc)
      self.content = action_doc.content
      self.meta = action_doc.meta
      self.state = action_doc.state
    end

    private def update_pending_work
      @db_doc['pending_work'] = @db_doc['pending_actions'].any?
    end
  end
end
