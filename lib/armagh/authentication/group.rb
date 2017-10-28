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
require_relative '../document/base_document/document'

module Armagh
  module Authentication

    class User < BaseDocument::Document; end

    class Group < BaseDocument::Document

      class GroupError < StandardError; end
      class PermanentError < GroupError; end
      class NameError < GroupError; end
      class DescriptionError < GroupError; end
      class RoleError < GroupError; end
      class UserError < GroupError; end

      delegated_attr_accessor :name, validates_with: :clean_name
      delegated_attr_accessor :description, validates_with: :clean_description
      delegated_attr_accessor :directory
      delegated_attr_accessor_array :users, references_class: User
      delegated_attr_accessor_array :roles, references_class: Role
      delegated_attr_accessor :permanent

      alias_method :add_role, :add_item_to_roles
      alias_method :remove_role, :remove_item_from_roles
      alias_method :remove_all_roles, :clear_roles

      def clean_name(name)
        raise NameError, 'Name must be a nonempty string.' unless name.is_a?(String) && !name.empty?
        lowercase = name.downcase
        raise NameError, 'Name can only contain alphabetic, numeric, and underscore characters.' if lowercase =~ /\W/
        lowercase
      end

      def clean_description(description)
        raise DescriptionError, 'Description must be a nonempty string.' unless description.is_a?(String) && !description.empty?
        description
      end

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
        group = find_by_name(name)

        if group.nil?
          group = new({
              'name' => name,
              'description' => description,
              'directory' => Directory::INTERNAL
          })
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
        create_one({
            'name' => name,
            'description' => description,
            'directory' => directory
        })
      rescue Connection::DocumentUniquenessError
        raise NameError, "A group with name '#{name}' already exists."
      end

      def self.update(id:, name:, description:)
        doc = get(id)

        if doc
          doc.name = name
          doc.description = description
          doc.save
        end

        doc
      end

      def self.find_by_name(name)
        find_one( { 'name' => name })
      end

      def self.find_all(ids = nil)
        qualifier = {}
        qualifier['_id' ] = { '$in' => ids.collect{ |id|  id.is_a?(String) ? BSON::ObjectId.from_string(id) : id }} if ids
        find_many( qualifier ).to_a.compact
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{self.class} #{(ids||[]).join(', ')}" )
      end

      def delete
        raise PermanentError, 'Cannot delete a permanent account.' if permanent?
        users.each {|u| remove_user(u)}
        super
        true
      end

      def has_user?(user)
        users.include? user
      end

      def add_user(user, reciprocate: true)
        return if has_user? user
        add_item_to_users user
        if reciprocate
          user.join_group(self, reciprocate: false)
          user.save
        end
      end

      def remove_user(user, reciprocate: true)
        if has_user?(user)
          remove_item_from_users user

          if reciprocate
            user.leave_group(self, reciprocate: false)
            user.save
          end
        else
          raise UserError, "User '#{user.username}' is not a member of '#{name}'."
        end
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
        permanent || false
      end

      def mark_permanent
        self.permanent = true
      end

      def ==(other)
        other.is_a?(Group) && self.internal_id == other.internal_id
      end

      def hash
        internal_id.to_s.hash
      end

      def eql?(other)
        self == other
      end

      def to_json(options = {})
        hash = to_hash
        hash['users'] ||= []
        hash['users'].collect!{ |u| u.to_s }
        hash.to_json(options)
      end

    end
  end
end
