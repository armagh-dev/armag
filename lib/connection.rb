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

require 'set'

require_relative 'connection/mongo_connection'
require_relative 'connection/mongo_admin_connection'

module Armagh
  module Connection
    def self.all_document_collections
      doc_collections = []

      MongoConnection.instance.connection.collections.each do |collection|
        doc_collections << collection if collection.name =~ /^documents\./
      end

      doc_collections << documents
    end

    def self.documents(type_collection = nil)
      collection_name = type_collection ? "documents.#{type_collection}" : 'documents'
      collection = MongoConnection.instance.connection[collection_name]
      index_doc_collection collection
      collection
    end

    def self.archive
      MongoConnection.instance.connection['archive']
    end

    def self.failures
      MongoConnection.instance.connection['failures']
    end

    def self.config
      MongoConnection.instance.connection['config']
    end

    def self.users
      MongoConnection.instance.connection['users']
    end

    def self.status
      MongoConnection.instance.connection['status']
    end

    def self.log
      MongoConnection.instance.connection['log']
    end

    def self.resource_config
      MongoAdminConnection.instance.connection['resource']
    end

    def self.resource_log
      MongoAdminConnection.instance.connection['log']
    end

    def self.master?
      # TODO Connection.master?  Is this a primary server?
    end

    def self.primaries
      # TODO Connection.primaries Get the Primary Servers
    end

    def self.can_connect?
      begin
        connectable = false
        MongoConnection.instance.connection.cluster.servers.each do |server|
          if server.connectable?
            connectable = true
            break
          end
        end
        connectable
      rescue
        false
      end
    end

    def self.clear_indexed_doc_collections
      @indexed_doc_collections.clear if @indexed_doc_collections
    end

    def self.setup_indexes
      config.indexes.create_one({'type' => 1}, unique: true, name: 'types')
      all_document_collections.each { |c| index_doc_collection(c) }
    end

    def self.index_doc_collection(collection)
      @indexed_doc_collections ||= Set.new
      return unless @indexed_doc_collections.add?(collection.name)

      # Unlocked Documents by ID (Document#find_or_create_and_lock) not needed to be indexed because ids are unique (mongo reverts to _id_ index)

      # Unlocked documents pending work
      collection.indexes.create_one({'pending_work' => 1, 'locked' => 1, 'updated_timestamp' => 1},
                                    name: 'pending_unlocked',
                                    partial_filter_expression: {
                                        'pending_work' => {'$exists' => true},
                                        'locked' => false
                                    })
    end
  end
end
