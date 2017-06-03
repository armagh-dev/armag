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

require_relative '../connection'

module Armagh
  module Authentication
    class Role
      attr_reader :name, :description, :key

      class << self
        protected :new
      end

      def self.all
        roles = PREDEFINED_ROLES.dup
        Connection.all_published_collections.each do |collection|
          roles << published_collection_role(collection)
        end
        roles
      end

      def self.published_collection_role(published_collection)
        name = published_collection.name.sub('documents.', '')
        new(name: "#{name} User", description: "Can view all published #{name} documents", key: "doc_#{name}_user", published_collection_role: true)
      end

      def self.find(role_key)
        all.each {|r| return r if r.key == role_key}
        nil
      end

      def initialize(name:, description:, key:, published_collection_role: false)
        @name = name
        @description = description
        @key = key
        @published_collection_role = published_collection_role
      end

      def published_collection_role?
        @published_collection_role
      end

      def ==(other)
        other.is_a?(Role) && @key == other.key
      end

      def hash
        @key.hash
      end

      def to_hash
        {
            'name' => @name,
            'description' => @description,
            'key' => @key,
            'published_collection_role' => @published_collection_role
        }

      end

      def to_json(options = {})
        to_hash.to_json(options)
      end

      def eql?(other)
        self == other
      end

      PREDEFINED_ROLES = [
        APPLICATION_ADMIN = new(name: 'Application Admin', description: 'Ability to modify behavior of Armagh', key: 'application_admin'),
        RESOURCE_ADMIN = new(name: 'Resource Admin', description: 'Ability to modify resource configuration', key: 'resource_admin'),
        USER_ADMIN = new(name: 'User Admin', description: 'Ability to add, delete, and modify users', key: 'user_admin'),
        USER_MANAGER = new(name: 'User Manager', description: 'Ability to reset user passwords and unlock users', key: 'user_manager'),
        USER = new(name: 'User', description: 'Can view all published documents', key: 'doc_user')
      ].freeze
    end
  end
end