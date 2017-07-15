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

require 'facets/kernel/deep_copy'

module Armagh
  module Connection
    class DBDoc
      def self.default_collection
        nil
      end

      attr_reader :db_doc

      class << self
        protected :new
      end

      def initialize(image = {})
        @db_doc = image
        Utils::DBDocHelper.restore_model(self)
      end

      def internal_id
        @db_doc['_id']
      end

      def internal_id=(id)
        @db_doc['_id'] = id
      end

      def mark_timestamp
        now = Time.now
        self.updated_timestamp = now
        self.created_timestamp ||= now
      end

      def updated_timestamp
        @db_doc['updated_timestamp']&.utc
      end

      def updated_timestamp=(ts)
        @db_doc['updated_timestamp'] = ts
      end

      def created_timestamp
        @db_doc['created_timestamp']&.utc
      end

      def created_timestamp=(ts)
        @db_doc['created_timestamp'] = ts
      end

      def self.db_create(values, collection = self.default_collection)
        check_collection(collection)
        collection.insert_one(values).inserted_ids.first
      end

      def self.db_find_one(qualifier, collection = self.default_collection)
        db_find(qualifier, collection).limit(1).first
      end

      def self.db_find(qualifier, collection = self.default_collection)
        check_collection(collection)
        collection.find(qualifier)
      end

      def self.db_find_and_update(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.find_one_and_update(qualifier, {'$set': values}, {return_document: :after, upsert: true})
      end

      def self.db_update(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.update_one(qualifier, {'$setOnInsert': values}, {upsert: true})
      end

      def self.db_replace(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.replace_one(qualifier, values, {upsert: true})
      end

      def self.db_delete(qualifier, collection = self.default_collection)
        check_collection(collection)
        collection.delete_one(qualifier)
      end

      def inspect
        to_hash.inspect
      end

      def to_s
        to_hash.to_s
      end

      def to_hash
        @db_doc.deep_copy
      end

      def to_json(options = {})
        hash = to_hash
        hash['_id'] = hash['_id'].to_s if hash['_id']
        hash.to_json(options)
      end

      def self.check_collection(collection)
        raise ArgumentError, 'No collection specified.  Make sure <model>.default_collection is defined.' unless collection
      end
    end
  end
end
