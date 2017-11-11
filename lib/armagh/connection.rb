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

require 'set'

require_relative 'configuration/file_based_configuration'
require_relative 'connection/mongo_error_handler'
require_relative 'connection/mongo_connection'
require_relative 'connection/mongo_admin_connection'
require_relative 'utils/network_helper'

module Armagh
  module Connection

    class ConnectionError < StandardError; end
    class IndexError < ConnectionError; end
    class DocumentSizeError < ConnectionError; end
    class DocumentUniquenessError < ConnectionError; end

    def self.published_collection?(collection)
      collection.name =~ /^documents\./
    end

    def self.all_document_collections
      collections = all_published_collections
      collections.unshift documents
      collections
    end

    def self.all_published_collections
      published_collections = []

      MongoConnection.instance.connection.collections.each do |collection|
        published_collections << collection if published_collection?(collection)
      end

      published_collections
    end

    def self.documents(type_name = nil)
      collection_name = type_name ? "documents.#{ type_name }" : 'documents'
      collection = MongoConnection.instance.connection[collection_name]
      index_doc_collection collection
      collection
    end

    def self.collection_history
      MongoConnection.instance.connection['collection_history']
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

    def self.groups
      MongoConnection.instance.connection['groups']
    end

    def self.launcher_status
      MongoConnection.instance.connection['launcher_status']
    end

    def self.agent_status
      MongoConnection.instance.connection['agent_status']
    end

    def self.action_state
      MongoConnection.instance.connection['action_state']
    end

    def self.semaphores
      MongoConnection.instance.connection['semaphores']
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

    def self.ip
      MongoConnection.instance.ip
    end

    def self.master?
      MongoConnection.instance.connection.database.command(ismaster: 1).documents.first['ismaster']
    end

    def self.primaries
      primary_hosts = []
      MongoConnection.instance.connection.cluster.servers.each do |server|
        primary_hosts << server.address.host if server.primary?
      end
      primary_hosts
    end

    def self.can_connect?
      @can_connect_message = nil
      servers = MongoConnection.instance.connection.cluster.servers
      if servers.empty?
        @can_connect_message = 'The database does not appear to be running.'
        return false
      end

      servers.each do |server|
        server.with_connection do |conn|
          return true if conn.ping
        end
      end
      false
    rescue => e
      @can_connect_message = e.message
      false
    end

    def self.can_connect_message
      @can_connect_message
    end

    def self.require_connection(logger = nil)
      unless Connection.can_connect?
        Logging.disable_mongo_log
        msg = "Unable to establish connection to the MongoConnection database configured in '#{Configuration::FileBasedConfiguration.filepath}'.  #{Connection.can_connect_message}"
        if logger
          logger.error msg
        else
          $stderr.puts msg
        end
        exit 1
      end
    end

    def self.clear_indexed_doc_collections
      @indexed_doc_collections.clear if @indexed_doc_collections
    end

    def self.setup_indexes
      config.indexes.create_one({'type' => 1, 'name' => 1, 'timestamp' => -1}, unique: true, name: 'types')
      action_state.indexes.create_one({'name' => 1}, unique: true, name: 'names')
      users.indexes.create_one({'username' => 1}, unique: true, name: 'usernames')
      groups.indexes.create_one({'name' => 1}, unique: true, name: 'names')
      agent_status.indexes.create_one({'hostname' => 1}, unique: false, name: 'hostnames')
      semaphores.indexes.create_one( {'name' => 1}, unique: true, name: 'names')

      all_document_collections.each { |c| index_doc_collection(c) }
    rescue => e
      e = Connection.convert_mongo_exception(e)
      raise IndexError, "Unable to create indexes: #{e.message}"
    end

    def self.index_doc_collection(collection)
      @indexed_doc_collections ||= Set.new
      return unless @indexed_doc_collections.add?(collection.name)

      # Unlocked Documents by ID (Document#find_or_create_and_lock) not needed to be indexed because ids are unique (mongo reverts to _id_ index)

      if published_collection?(collection)
        collection.indexes.create_one({'document_id' => 1},
                                      unique: true,
                                      partial_filter_expression: {'document_id' => {'$exists' => true} },
                                      name: 'published_document_ids')
      else
        collection.indexes.create_one({'document_id' => 1, 'type' => 1},
                                      unique: true,
                                      partial_filter_expression: {'document_id' => {'$exists' => true} },
                                      name: 'document_ids')
      end

      # Unlocked documents pending work
      collection.indexes.create_one({'pending_work' => 1, 'updated_timestamp' => 1 },
                                    name: 'pending_unlocked',
                                    partial_filter_expression: { 'pending_work' => {'$exists' => true }, '_locked' => false }
      )

      # locked documents; needed by db_cleanup_utility_action
      collection.indexes.create_one( {'_locked.until' => 1 }, name: 'locked_docs')

    rescue => e
      raise IndexError, "Unable to create index for collection #{collection.name}: #{e.message}"
    end
  end
end
