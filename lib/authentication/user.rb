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

require_relative '../connection'
require_relative '../utils/password'

require 'armagh/support/random'
require 'base64'

module Armagh
  module Authentication
    class User < Connection::DBDoc

      class UserError < StandardError; end
      class AccountError < UserError; end
      class UsernameError < UserError; end
      class DirectoryError < UserError; end
      class PermanentError < UserError; end

      MAX_TRIES = 3 # TODO Make this configurable
      DUMMY_USERNAME = '__dummy_users__'
      ADMIN_USERNAME = 'admin'
      DEFAULT_ADMIN_PASSWORD = 'armaghadmin'

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
          @dummy_user.password = Armagh::Support::Random.random_str(32)
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
        @dummy_user.unlock
        @dummy_user.enable
        @dummy_user.db_doc['attempted_usernames'][username] ||= 0
        @dummy_user.db_doc['attempted_usernames'][username] += 1
        @dummy_user.lock if @dummy_user.db_doc['attempted_usernames'][username] >= MAX_TRIES
        @dummy_user.authenticate(pass)
        return nil
      end

      def self.create(username:, password:, directory: Directory::INTERNAL)
        # TODO When directory is LDAP, copy the details from the LDAP server into this  (ARM-213)
        new_user = new
        new_user.directory = directory
        new_user.username = username
        new_user.password = password if directory == Directory::INTERNAL
        new_user.save
        new_user
      end

      def self.find_username(username)
        lowercase = username.downcase
        user = self.db_find_one({'username' => lowercase})
        user ? new(user) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: lowercase, type_class: self.class)
      end

      def self.find(id)
        user = self.db_find_one({'_id' => id})
        user ? new(user) : nil
      rescue => e
        raise Connection.convert_mongo_exception(e, id: id, type_class: self.class)
      end

      def self.find_all(internal_ids)
        ids = Array(internal_ids)
        users = []

        db_users = self.db_find({'_id' => {'$in' => ids}}).to_a.compact

        db_users.each do |db_user|
          users << new(db_user)
        end

        users
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_ids.join(', '), type_class: self.class)
      end

      def self.authenticate(username, pass)
        user = find_username(username)
        if user
          if username == DUMMY_USERNAME
            # They tried to log in as the dummy user.  Do the authentication but always fail
            return auth_dummy_user(username, pass)
          else
            # They logged in with a valid username
            return user.authenticate(pass) ? user : nil
          end
        else
          return auth_dummy_user(username, pass)
        end
      end

      def initialize(image = {})
        super
        @db_doc['roles'] ||= []
        @db_doc['groups'] ||= []
        @db_doc['auth_failures'] ||= 0
      end

      def refresh
        @db_doc = self.class.db_find_one({'_id' => internal_id})
      end

      def authenticate(pass)
        raise AccountError, 'Account Locked' if locked?
        raise AccountError, 'Account Disabled' if disabled?

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
          lock if auth_failures >= MAX_TRIES && !permanent?
        end

        save(update_timestamps: false)
        result
      end

      def save(update_timestamps: true)
        self.mark_timestamp if update_timestamps

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
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def username
        @db_doc['username']
      end

      def username=(username)
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
        Utils::Password.verify_strength password
        @db_doc['hashed_password'] = Utils::Password.hash(password)
        @db_doc['password_timestamp'] = Time.now
        clear_password_reset
      end

      def password_timestamp
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        @db_doc['password_timestamp']
      end

      def reset_password
        random_password = Utils::Password.random_password
        self.password = random_password
        mark_password_reset
        save
        random_password
      end

      def name
        @db_doc['name']
      end

      def name=(name)
        @db_doc['name'] = name
      end

      def email
        @db_doc['email']
      end

      def email=(email)
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
        @db_doc['groups'] << group.internal_id
        if reciprocate
          group.add_user(self, reciprocate: false)
          group.save
        end
      end

      def leave_group(group, reciprocate: true)
        @db_doc['groups'].delete group.internal_id
        if reciprocate
          group.remove_user(self, reciprocate: false)
          group.save
        end
      end

      def member_of?(group)
        @db_doc['groups'].include? group.internal_id
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
        @db_doc['roles'].delete role.key
      end

      def remove_all_roles
        @db_doc['roles'].clear
      end

      def has_role?(role)
        all_roles.values.flatten.uniq.each do |r|
          return true if role == r || (r == Role::USER && role.published_collection_role?)
        end
        false
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
    end
  end
end
