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

require_relative 'connection/mongo_connection'
require_relative 'connection/mongo_admin_connection'

module Armagh
  module Connection
    # TODO Connection Set up indexes HERE! not elsewhere in the code

    def self.all_document_collections
      doc_collections = []

      MongoConnection.instance.connection.collections.each do |collection|
        doc_collections << collection if collection.name =~ /^documents\./
      end

      doc_collections << documents
    end

    def self.documents(type_collection = nil)
      collection = type_collection ? "documents.#{type_collection}" : 'documents'
      MongoConnection.instance.connection[collection]
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
  end
end
