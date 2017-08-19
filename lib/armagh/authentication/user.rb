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
require_relative 'group'
require_relative 'role'

require_relative 'configuration'
require_relative '../connection'
require_relative '../utils/db_doc_helper'
require_relative '../utils/password'

require 'armagh/support/random'
require 'base64'
require 'bson'

module Armagh
  module Authentication
    class User < Connection::DBDoc

      class UserError < StandardError; end
      class UsernameError < UserError; end
      class NameError < UserError; end
      class EmailError < UserError; end
      class DirectoryError < UserError; end
      class PermanentError < UserError; end
      class RoleError < UserError; end
      class GroupError < UserError; end

      DUMMY_USERNAME = '__dummy_user__'
      ADMIN_USERNAME = 'admin'
      DEFAULT_ADMIN_PASSWORD = 'armaghadmin'

      VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

      def self.default_collection
        Connection.users
      end

      def self.setup_default_users
        setup_admin_user
        setup_dummy_user
      end

      # Create a dummy user to make authentication that fails due to a missing user behave the same way as if the user
      #  was valid.  This is a security mechanism to limit attackers' abilities to determine which users are valid.
      private_class_method def self.setup_dummy_user
        @dummy_user = find_username(DUMMY_USERNAME)

        if @dummy_user.nil?
          @dummy_user = new
          @dummy_user.username = DUMMY_USERNAME
          @dummy_user.directory = Directory::INTERNAL
          @dummy_user.password = Support::Random.random_str(32)
          @dummy_user.db_doc['attempted_usernames'] = {}
          @dummy_user.save
        end
      end

      private_class_method def self.setup_admin_user
        admin = find_username(ADMIN_USERNAME)

        if admin.nil?
          admin = new
          admin.username = ADMIN_USERNAME
          admin.directory = Directory::INTERNAL
          admin.password = DEFAULT_ADMIN_PASSWORD
          admin.mark_permanent
          admin.mark_password_reset
        end

        # Give admin all predefined roles
        admin.remove_all_roles
        Role::PREDEFINED_ROLES.each {|role| admin.add_role role}
        admin.save
      end

      private_class_method def self.auth_dummy_user(username, pass)
        Authentication.config.refresh
        @dummy_user.unlock
        @dummy_user.enable
        @dummy_user.db_doc['attempted_usernames'][username] ||= 0
        @dummy_user.db_doc['attempted_usernames'][username] += 1
        @dummy_user.lock if @dummy_user.db_doc['attempted_usernames'][username] >= Authentication.config.authentication.max_login_attempts
        @dummy_user.authenticate(pass)
        return nil
      end

      def self.create(username:, password:, name:, email:, directory: Directory::INTERNAL)
        # TODO When directory is LDAP, copy the details from the LDAP server into this  (ARM-213)
        new_user = new
        new_user.directory = directory
        new_user.username = username
        new_user.name = name
        new_user.email = email
        new_user.password = password if directory == Directory::INTERNAL
        new_user.save
        new_user
      rescue Connection::DocumentUniquenessError
        raise UsernameError, "A user with username '#{username}' already exists."
      end

      def self.update(id:, username:, password:, name:, email:)
        doc = find(id)

        if doc
          doc.username = username
          doc.password = password if password
          doc.name = name
          doc.email = email
          doc.save
        end

        doc
      end

      def self.find_username(username)
        lowercase = username.downcase
        user = self.db_find_one({'username' => lowercase})
        user ? new(user) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: lowercase, type_class: self.class)
      end

      def self.find(id)
        id = BSON::ObjectId.from_string(id.to_s)
        user = self.db_find_one({'_id' => id})
        user ? new(user) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: id, type_class: self.class)
      end

      def self.find_all(internal_ids = nil)
        if internal_ids
          ids = Array(internal_ids).collect{|id| BSON::ObjectId.from_string(id)}
          db_users = self.db_find({'_id' => {'$in' => ids}}).to_a.compact
        else
          db_users = self.db_find({}).to_a.compact
        end

        users = []

        db_users.each do |db_user|
          users << new(db_user)
        end

        users
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_ids.join(', '), type_class: self.class)
      end

      def self.authenticate(username, pass)
        valid = false
        user = find_username(username)
        if user.nil? || username == DUMMY_USERNAME
          # They tried to log in as the dummy user or an non-existent user.  Do the authentication but always fail
          auth_dummy_user(username, pass)
        else
          # They logged in with a valid username
          valid = user.authenticate(pass)
        end
        raise AuthenticationError, "Authentication failed for #{username}." unless valid
        user
      end

      def initialize(image = {})
        image['_id'] = image['id'] unless image.key? '_id'
        image.delete('id')

        super

        @db_doc['roles'] ||= []
        @db_doc['groups'] ||= []
        @db_doc['auth_failures'] ||= 0
      end

      def refresh
        @db_doc = self.class.db_find_one({'_id' => internal_id})
        Utils::DBDocHelper.restore_model(self)
        @db_doc
      end

      def authenticate(pass)
        raise AuthenticationError, 'Account Locked' if locked?
        raise AuthenticationError, 'Account Disabled' if disabled?

        Authentication.config.refresh

        if directory == Directory::INTERNAL
          result = Utils::Password.correct?(pass, hashed_password)
        elsif directory == Directory::LDAP
          # TODO Add LDAP Authentication (ARM-213)
          result = false
        end

        if result
          reset_auth_failures
          mark_last_login
        else
          increment_auth_failures
          lock if auth_failures >= Authentication.config.authentication.max_login_attempts && !permanent?
        end

        save(update_timestamps: false)
        result
      end

      def save(update_timestamps: true)
        self.mark_timestamp if update_timestamps

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
        groups.each {|g| leave_group(g)}
        self.class.db_delete({'_id' => internal_id})
        true
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def username
        @db_doc['username']
      end

      def username=(username)
        raise UsernameError, 'Username must be a nonempty string.' unless username.is_a?(String) && !username.empty?
        lowercase = username.downcase
        raise UsernameError, 'Username can only contain alphabetic, numeric, and underscore characters.' if lowercase =~ /\W/
        @db_doc['username'] = lowercase
      end

      def hashed_password
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc['hashed_password']
      end

      def password=(password)
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        Authentication.config.refresh
        Utils::Password.verify_strength(password, Authentication.config.authentication.min_password_length)
        @db_doc['hashed_password'] = Utils::Password.hash(password)
        @db_doc['password_timestamp'] = Time.now
        clear_password_reset
      end

      def password_timestamp
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc['password_timestamp']
      end

      def reset_password
        Authentication.config.refresh
        random_password = Utils::Password.random_password(Authentication.config.authentication.min_password_length)
        self.password = random_password
        mark_password_reset
        save
        random_password
      end

      def name
        @db_doc['name']
      end

      def name=(name)
        raise NameError, 'Name must be a nonempty string.' unless name.is_a?(String) && !name.empty?
        @db_doc['name'] = name
      end

      def email
        @db_doc['email']
      end

      def email=(email)
        raise EmailError, 'Email must be a nonempty string.' unless email.is_a?(String) && !email.empty?
        raise EmailError, 'Email format is invalid.'unless email =~ VALID_EMAIL_REGEX
        @db_doc['email'] = email
      end

      def auth_failures
        @db_doc['auth_failures']
      end

      def increment_auth_failures
        @db_doc['auth_failures'] += 1
      end

      def reset_auth_failures
        @db_doc['auth_failures'] = 0
      end

      def last_login
        @db_doc['last_login']
      end

      def mark_last_login
        @db_doc['last_login'] = Time.now
      end

      def lock
        raise PermanentError, 'Cannot lock a permanent account.' if permanent?
        @db_doc['locked'] = true
      end

      def unlock
        @db_doc.delete 'locked'
      end

      def locked?
        @db_doc['locked'] || false
      end

      def mark_password_reset
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc['required_password_reset'] = true
      end

      def clear_password_reset
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc.delete('required_password_reset')
      end

      def required_password_reset?
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc['required_password_reset'] || false
      end

      def directory
        @db_doc['directory']
      end

      def directory=(directory)
        raise PermanentError, 'Cannot change directory of a permanent account.' if permanent?
        @db_doc['directory'] = directory
      end

      def enable
        @db_doc.delete 'disabled'
      end

      def disable
        raise PermanentError, 'Cannot disable a permanent account.' if permanent?
        @db_doc['disabled'] = true
      end

      def disabled?
        @db_doc['disabled'] || false
      end

      def groups
        if @db_doc['groups'].empty?
          []
        else
          Group.find_all(@db_doc['groups'])
        end
      end

      def join_group(group, reciprocate: true)
        return if member_of? group
        @db_doc['groups'] << group.internal_id.to_s
        if reciprocate
          group.add_user(self, reciprocate: false)
          group.save
        end
      end

      def leave_group(group, reciprocate: true)
        if member_of?(group)
          @db_doc['groups'].delete group.internal_id.to_s
          if reciprocate
            group.remove_user(self, reciprocate: false)
            group.save
          end
        else
          raise GroupError, "User '#{username}' is not a member of '#{group.name}'."
        end
      end

      def member_of?(group)
        @db_doc['groups'].include? group.internal_id.to_s
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

      def all_roles
        all_roles = {'self' => roles}

        groups.each do |group|
          group_roles = group.roles
          all_roles[group.name] = group_roles unless group_roles.empty?
        end

        all_roles
      end

      def add_role(role)
        role_key = role.key
        @db_doc['roles'] << role_key unless @db_doc['roles'].include? role_key
      end

      def remove_role(role)
        if has_direct_role? role
          @db_doc['roles'].delete role.key
        else
          raise RoleError, "User '#{username}' does not have a direct role of '#{role.key}'."
        end
      end

      def remove_all_roles
        @db_doc['roles'].clear
      end

      def has_direct_role?(role)
        roles.each do |r|
          return true if role == r || (r == Role::USER && role.published_collection_role?)
        end
        false
      end

      def has_role?(role)
        return false if role.nil?
        has_role = false
        all_roles.values.flatten.uniq.each do |r|
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
        other.is_a?(User) && self.internal_id == other.internal_id
      end

      def hash
        internal_id.hash
      end

      def eql?(other)
        self == other
      end

      def to_hash
        hash = super
        hash['disabled'] = disabled?
        hash['locked'] = locked?
        hash['permanent'] = permanent?
        hash
      end

      def to_json(options = {})
        hash = to_hash
        hash['id'] = hash['_id'].nil? ? nil : hash['_id'].to_s
        hash.delete('_id')
        hash.delete('hashed_password')
        hash.to_json(options)
      end

      alias_method :id, :internal_id
    end
  end
end
