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
require_relative '../connection'

module Armagh
  # Document States
  #   Closed
  #   Pending
  #   Published
  class Document

    def self.create(type, content, meta, pending_actions, id=nil)
      doc = Document.new
      doc.type = type
      doc.content = content
      doc.meta = meta
      doc.id = id if id
      doc.add_pending_actions pending_actions
      doc.save
      doc
    end

    def self.find(id)
      db_doc = Connection.documents.find('_id' => id).limit(1).first
      db_doc ? Document.new(db_doc) : nil
    end

    def self.get_for_processing
      # TODO find a document in the following order
      #  Oldest -> Newest: No local agent picked up for too long
      #  Oldest -> Newest: local
      # TODO Doc must be in a valid state
      # TODO Doc must not be locked
      # TODO lock the doc
      db_doc = Connection.documents.find_one_and_update({'pending_work' => true}, {'$set' => {'locked': true }}, :return_document => :after)
      db_doc ? Document.new(db_doc) : nil
    end

    protected def new(*args)
      super(args)
    end

    protected def initialize(image = {})
      @db_doc = {'meta' => {}, 'content' => nil, 'md5' => nil, 'type' => nil, 'pending_actions' => [], 'locked' => false, 'pending_work' => false, 'created_timestamp' => nil, 'updated_timestamp' => nil}
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
      @db_doc['pending_actions'].concat(actions.flatten)
      update_pending_work
    end

    def remove_pending_action(action)
      @db_doc['pending_actions'].delete(action)
      update_pending_work
    end

    def pending_actions
      @db_doc['pending_actions']
    end

    def pending_work
      @db_doc['pending_work']
    end

    def unlock
      Connection.documents.update_one({ '_id': id}, '$set' => { 'locked' => false})
      @db_doc['locked'] = false
    end

    def lock
      Connection.documents.update_one({ '_id': id}, '$set' => { 'locked' => true})
      @db_doc['locked'] = true
    end

    def locked?
      @db_doc['locked']
    end

    def save
      now = Time.now
      @db_doc['created_timestamp'] ||= now
      @db_doc['updated_timestamp'] = now

      if id
        Connection.documents.replace_one({ '_id': id}, @db_doc)
      else
        @db_doc['_id'] = Connection.documents.insert_one(@db_doc)
      end
    end

    def publish
      # TODO
      #if publishable
      #  meta[ 'state' ] = 'published'
      #  meta[ 'triggering_subscribers' ] = from doc configuration
      #  meta[ 'subscribers' ] = from doc configuration
      #  meta[ 'updated_at' ] = Time.now
      #  # need to let action set the document timestamp?
      #end
    end

    def close
      # TODO
      #if published and no subscribers left
      #  meta[ 'state' ] = closed
      #  my config.closure_policy.call
      #end
    end

    private def update_pending_work
      @db_doc['pending_work'] = @db_doc['pending_actions'].any?
    end
  end
end
