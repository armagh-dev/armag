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

require 'bson'

require_relative 'directory'
require_relative 'role'
require_relative 'user'

require_relative '../connection'
require_relative '../utils/db_doc_helper'

module Armagh
  module Authentication
    class Group < Connection::DBDoc

      class GroupError < StandardError; end
      class PermanentError < GroupError; end
      class NameError < GroupError; end
      class DescriptionError < GroupError; end
      class RoleError < GroupError; end
      class UserError < GroupError; end

      def self.default_collection
        Connection.groups
      end

      def self.setup_default_groups
        setup_sa_group
        setup_admin_group
        setup_user_admin_group
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
        group = setup_group 'super_administrators', 'Full control over Armagh'
        Role::PREDEFINED_ROLES.each {|role| group.add_role role}
        group.save
      end

      private_class_method def self.setup_admin_group
        group = setup_group 'administrators', 'Modify behavior of Armagh'
        group.add_role Role::APPLICATION_ADMIN
        group.add_role Role::USER_ADMIN
        group.add_role Role::USER
        group.save
      end

      private_class_method def self.setup_user_admin_group
        group = setup_group 'user_administrators', 'Add, delete, and modify users'
        group.add_role Role::USER_ADMIN
        group.add_role Role::USER
        group.save
      end

      private_class_method def self.setup_user_group
        group = setup_group 'users', 'View documents'
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
      rescue Connection::DocumentUniquenessError
        raise NameError, "A group with name '#{name}' already exists."
      end

      def self.update(id:, name:, description:)
        doc = find(id)

        if doc
          doc.name = name
          doc.description = description
          doc.save
        end

        doc
      end

      def self.find(id)
        id = BSON::ObjectId.from_string(id.to_s)
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

      def self.find_all(ids = nil)
        if ids
          ids = Array(ids).collect{|id| BSON::ObjectId.from_string(id)}
          db_groups = self.db_find({'_id' => {'$in' => ids}}).to_a.compact
        else
          db_groups = self.db_find({}).to_a.compact
        end

        groups = []

        db_groups.each do |db_group|
          groups << new(db_group)
        end

        groups
      rescue => e
        raise Connection.convert_mongo_exception(e, id: ids.join(', '), type_class: self.class)
      end

      def initialize(image = {})
        image['_id'] = image['id'] unless image.key? '_id'
        image.delete('id')

        super
        @db_doc['roles'] ||= []
        @db_doc['users'] ||= []
      end

      def refresh
        @db_doc = self.class.db_find_one({'_id' => internal_id})
        Utils::DBDocHelper.restore_model(self)
        @db_doc
      end

      def save
        self.mark_timestamp

        Utils::DBDocHelper.clean_model(self)

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
        true
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def name
        @db_doc['name']
      end

      def name=(name)
        raise NameError, 'Name must be a nonempty string.' unless name.is_a?(String) && !name.empty?
        lowercase = name.downcase
        raise NameError, 'Name can only contain alphabetic, numeric, and underscore characters.' if lowercase =~ /\W/
        @db_doc['name'] = lowercase
      end

      def description
        @db_doc['description']
      end

      def description=(description)
        raise DescriptionError, 'Description must be a nonempty string.' unless description.is_a?(String) && !description.empty?
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
        @db_doc['users'].include? user.internal_id.to_s
      end

      def add_user(user, reciprocate: true)
        return if has_user? user
        @db_doc['users'] << user.internal_id.to_s
        if reciprocate
          user.join_group(self, reciprocate: false)
          user.save
        end
      end

      def remove_user(user, reciprocate: true)
        if has_user?(user)
          @db_doc['users'].delete user.internal_id.to_s

          if reciprocate
            user.leave_group(self, reciprocate: false)
            user.save
          end
        else
          raise UserError, "User '#{user.username}' is not a member of '#{name}'."
        end
      end

      def add_role(role)
        role_key = role.key
        @db_doc['roles'] << role_key unless @db_doc['roles'].include? role_key
      end

      def remove_role(role)
        if has_role? role
          @db_doc['roles'].delete role.key
        else
          raise RoleError, "Group '#{name}' does not have a direct role of '#{role.key}'."
        end
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
        return false if role.nil?
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

      def to_json(options = {})
        hash = to_hash
        hash['id'] = hash['_id'].nil? ? nil : hash['_id'].to_s
        hash.delete('_id')
        hash.to_json(options)
      end

      alias_method :id, :internal_id
    end
  end
end
