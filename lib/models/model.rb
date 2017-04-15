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

module Armagh
  module Models
    class Model
      def self.default_collection
        nil
      end

      attr_reader :db_doc

      class << self
        protected :new
      end

      def initialize(image)
        @db_doc = image
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

      def to_json
        @db_doc.to_json
      end

      def self.check_collection(collection)
        raise ArgumentError, 'No collection specified.  Make sure <model>.default_collection is defined.' unless collection
      end
    end
  end
end
