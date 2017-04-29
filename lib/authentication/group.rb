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

require_relative 'directory'
require_relative 'role'
require_relative 'user'

require_relative '../connection'

module Armagh
  module Authentication
    class Group < Connection::DBDoc

      class GroupError < StandardError; end
      class PermanentError < GroupError; end

      def self.default_collection
        Connection.groups
      end

      def self.setup_default_groups
        setup_sa_group
        setup_admin_group
        setup_user_admin_group
        setup_user_management_group
        setup_user_group
      end

      private_class_method def self.setup_group(name, description)
        group = find_name(name)

        if group.nil?
          group = new()
          group.name = name
          group.description = description
          group.directory = Directory::INTERNAL
          group.mark_permanent
        end

        group.remove_all_roles
        group
      end

      private_class_method def self.setup_sa_group
        group = setup_group 'Super Administrators', 'Full control over Armagh'
        Role::PREDEFINED_ROLES.each {|role| group.add_role role}
        group.save
      end

      private_class_method def self.setup_admin_group
        group = setup_group 'Administrators', 'Modify behavior of Armagh'
        group.add_role Role::APPLICATION_ADMIN
        group.add_role Role::USER_ADMIN
        group.add_role Role::USER_MANAGER
        group.add_role Role::USER
        group.save
      end

      private_class_method def self.setup_user_admin_group
        group = setup_group 'User Administrators', 'Add, delete, and modify users'
        group.add_role Role::USER_ADMIN
        group.add_role Role::USER_MANAGER
        group.add_role Role::USER
        group.save
      end

      private_class_method def self.setup_user_management_group
        group = setup_group 'User Managers', 'Reset user passwords and unlock users'
        group.add_role Role::USER_MANAGER
        group.add_role Role::USER
        group.save
      end

      private_class_method def self.setup_user_group
        group = setup_group 'Users', 'View documents'
        group.add_role Role::USER
        group.save
      end

      def self.create(name:, description:, directory: Directory::INTERNAL)
        # TODO When directory is LDAP, copy the details from the LDAP server into this  (ARM-213)
        new_group = new
        new_group.name = name
        new_group.description = description
        new_group.directory = directory
        new_group.save
        new_group
      end

      def self.find(id)
        group = self.db_find_one({'_id' => id})
        group ? new(group) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: id, type_class: self.class)
      end

      def self.find_name(name)
        group = self.db_find_one({'name' => name})
        group ? new(group) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: name, type_class: self.class)
      end

      def self.find_all(ids)
        ids = Array(ids)
        groups = []

        db_groups = self.db_find({'_id' => {'$in' => ids}}).to_a.compact

        db_groups.each do |db_group|
          groups << new(db_group)
        end

        groups
      rescue => e
        raise Connection.convert_mongo_exception(e, id: ids.join(', '), type_class: self.class)
      end

      def initialize(image = {})
        super
        @db_doc['roles'] ||= []
        @db_doc['users'] ||= []
      end

      def refresh
        @db_doc = self.class.db_find_one({'_id' => internal_id})
      end

      def save
        self.mark_timestamp

        if internal_id
          self.class.db_replace({'_id' => internal_id}, @db_doc)
        else
          self.internal_id = self.class.db_create(@db_doc)
        end
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def delete
        raise PermanentError, 'Cannot delete a permanent account.' if permanent?
        users.each {|u| remove_user(u)}
        self.class.db_delete({'_id' => internal_id})
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def name
        @db_doc['name']
      end

      def name=(name)
        @db_doc['name'] = name
      end

      def description
        @db_doc['description']
      end

      def description=(description)
        @db_doc['description'] = description
      end

      def directory
        @db_doc['directory']
      end

      def directory=(directory)
        @db_doc['directory'] = directory
      end

      def users
        if @db_doc['users'].empty?
          []
        else
          User.find_all(@db_doc['users'])
        end
      end

      def has_user?(user)
        @db_doc['users'].include? user.internal_id
      end

      def add_user(user, reciprocate: true)
        @db_doc['users'] << user.internal_id
        if reciprocate
          user.join_group(self, reciprocate: false)
          user.save
        end
      end

      def remove_user(user, reciprocate: true)
        @db_doc['users'].delete user.internal_id

        if reciprocate
          user.leave_group(self, reciprocate: false)
          user.save
        end
      end

      def add_role(role)
        role_key = role.key
        @db_doc['roles'] << role_key unless @db_doc['roles'].include? role_key
      end

      def remove_role(role)
        @db_doc['roles'].delete role.key
      end

      def remove_all_roles
        @db_doc['roles'].clear
      end

      def roles
        roles = []
        missing_keys = []

        @db_doc['roles'].each do |role_key|
          role = Role.find(role_key)
          role ? roles << role : missing_keys << role_key
        end

        missing_keys.each { |key| @db_doc['roles'].delete key}
        roles.uniq!
        roles
      end

      def has_role?(role)
        has_role = false
        roles.each do |r|
          if role == r || (r == Role::USER && role.published_collection_role?)
            has_role = true
            break
          end
        end
        has_role
      end

      def permanent?
        @db_doc['permanent'] || false
      end

      def mark_permanent
        @db_doc['permanent'] = true
      end

      def ==(other)
        other.is_a?(Group) && self.internal_id == other.internal_id
      end

      def hash
        internal_id.hash
      end

      def eql?(other)
        self == other
      end
    end
  end
end
