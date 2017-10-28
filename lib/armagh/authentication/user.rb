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
require_relative '../document/base_document/document'
require_relative '../connection'
require_relative '../utils/password'

require 'armagh/support/random'
require 'base64'
require 'bson'

module Armagh
  module Authentication

    class Group < BaseDocument::Document; end
    class User < BaseDocument::Document

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

      delegated_attr_accessor :username, validates_with: :clean_username
      delegated_attr_accessor :directory, validates_with: :check_not_permanent_user
      delegated_attr_accessor :name, validates_with: :clean_name
      delegated_attr_accessor :email, validates_with: :clean_email
      delegated_attr_accessor :permanent
      delegated_attr_accessor :disabled
      delegated_attr_accessor :locked_out
      delegated_attr_accessor :hashed_password, after_return: :hashed_password_unless_external
      delegated_attr_accessor :password_timestamp, after_return: :password_timestamp_unless_external
      delegated_attr_accessor :required_password_reset
      delegated_attr_accessor :attempted_usernames
      delegated_attr_accessor_array :roles, references_class: Role
      delegated_attr_accessor_array :groups, references_class: Group
      delegated_attr_accessor :last_login
      delegated_attr_accessor :auth_failures

      alias_method :add_role, :add_item_to_roles
      alias_method :remove_role, :remove_item_from_roles
      alias_method :remove_all_roles, :clear_roles

      def clean_username(username)
        raise UsernameError, 'Username must be a nonempty string.' unless username.is_a?(String) && !username.empty?
        lowercase = username.downcase
        raise UsernameError, 'Username can only contain alphabetic, numeric, and underscore characters.' if lowercase =~ /\W/
        lowercase
      end

      def check_not_permanent_user(directory)
        raise PermanentError, 'Cannot change directory of a permanent account.' if permanent?
        directory
      end

      def clean_name(name)
        raise NameError, 'Name must be a nonempty string.' unless name.is_a?(String) && !name.empty?
        name
      end

      def clean_email(email)
        raise EmailError, 'Email must be a nonempty string.' unless email.is_a?(String) && !email.empty?
        raise EmailError, 'Email format is invalid.'unless email =~ VALID_EMAIL_REGEX
        email
      end

      def password=(password)
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        Utils::Password.verify_strength(password, hashed_password)
        self.hashed_password = Utils::Password.hash(password)
        self.password_timestamp = Time.now
        clear_password_reset
      end

      def hashed_password_unless_external( hashed_password )
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        hashed_password
      end

      def password_timestamp_unless_external( ts )
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        ts
      end

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
        @dummy_user = find_by_username(DUMMY_USERNAME)

        if @dummy_user.nil?
          @dummy_user = create_one(
                            { 'username' => DUMMY_USERNAME,
                              'directory' => Directory::INTERNAL,
                              'password' => Support::Random.random_str(32),
                              'attempted_usernames' => {}
                            }
          )
        end
      end

      private_class_method def self.setup_admin_user
        admin = find_by_username(ADMIN_USERNAME)

        if admin.nil?
          admin = new( {
            'username' => ADMIN_USERNAME,
            'directory' => Directory::INTERNAL,
            'password' => DEFAULT_ADMIN_PASSWORD
          })
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
        @dummy_user.remove_lock_out
        @dummy_user.enable
        @dummy_user.attempted_usernames[username] ||= 0
        @dummy_user.attempted_usernames[username] += 1
        @dummy_user.locked_out if @dummy_user.attempted_usernames[username] >= Authentication.config.authentication.max_login_attempts
        @dummy_user.authenticate(pass)
        return nil
      end

      def self.create(username:, password:, name:, email:, directory: Directory::INTERNAL)
        # TODO When directory is LDAP, copy the details from the LDAP server into this  (ARM-213)
         user_params = {
            'directory' => directory,
            'username' => username,
            'name' => name,
            'email' => email
        }
        user_params[ 'password' ] = password if directory == Directory::INTERNAL
        create_one( user_params )

      rescue Connection::DocumentUniquenessError
        raise UsernameError, "A user with username '#{username}' already exists."
      end

      def self.update( internal_id:, **options )
        user = get( internal_id )
        if user
          user.update( **options )
        end
      end

      def self.find_by_username(username)
        lowercase = username.downcase
        find_one({'username' => lowercase})
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{ self.class } #{ lowercase }")
      end

      def self.find_all(internal_ids = nil)
        qualifier = {}
        qualifier['_id' ] = { '$in' => internal_ids.collect{ |id|  id.is_a?(String) ? BSON::ObjectId.from_string(id) : id }} if internal_ids
        find_many( qualifier ).to_a.compact
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{self.class} #{internal_ids.join(', ') if internal_ids}")
      end

      def self.authenticate(username, pass)
        valid = false
        user = find_by_username(username)
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

      def initialize(image = {}, collection: self.class.default_collection )
        super
        self.disabled ||= false
        self.auth_failures ||= 0
        self.locked_out ||= false
        self.groups ||= []
        self.roles ||= []
      end

      def update(username:, password:, name:, email:)
        self.username = username
        self.password = password if password
        self.name = name
        self.email = email
        save
      end

      def authenticate(pass)
        raise AuthenticationError, 'Account Locked' if locked_out?
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
          lock_out if auth_failures >= Authentication.config.authentication.max_login_attempts && !permanent?
        end

        save(update_timestamps: false)
        result
      end

      def delete
        raise PermanentError, 'Cannot delete a permanent account.' if permanent?
        groups.each {|g| leave_group(g)}
        super
        true
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{self.class} #{internal_id}")
      end

      def reset_password
        random_password = Utils::Password.random_password
        self.password = random_password
        mark_password_reset
        save
        random_password
      end

       def increment_auth_failures
        self.auth_failures += 1
      end

      def reset_auth_failures
        self.auth_failures = 0
      end

      def mark_last_login
        self.last_login = Time.now
      end

      def lock_out
        raise PermanentError, 'Cannot lock out a permanent account.' if permanent?
        self.locked_out = true
      end

      def remove_lock_out
        raise PermanentError, 'Cannot remove lock-out on a permanent account.' if permanent?
        self.locked_out = false
      end

      def locked_out?
        locked_out || false
      end

      def mark_password_reset
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        self.required_password_reset = true
      end

      def clear_password_reset
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        delete_required_password_reset
      end

      def required_password_reset?
        raise DirectoryError, 'No password stored for external users.' unless directory == Directory::INTERNAL
        required_password_reset || false
      end

      def enable
        delete_disabled
      end

      def disable
        raise PermanentError, 'Cannot disable a permanent account.' if permanent?
        self.disabled = true
      end

      def disabled?
        disabled || false
      end

      def join_group(group, reciprocate: true)
        return if member_of? group
        add_item_to_groups group
        if reciprocate
          group.add_user(self, reciprocate: false)
          group.save
        end
      end

      def leave_group(group, reciprocate: true)
        if member_of?(group)
         remove_item_from_groups group
          if reciprocate
            group.remove_user(self, reciprocate: false)
            group.save
          end
        else
          raise GroupError, "User '#{username}' is not a member of '#{group.name}'."
        end
      end

      def member_of?(group)
        self.groups.include? group
      end

      def all_roles
        all_roles = {'self' => roles}

        groups.each do |group|
          group_roles = group.roles
          all_roles[group.name] = group_roles unless group_roles.empty?
        end

        all_roles
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
        permanent || false
      end

      def mark_permanent
        self.permanent = true
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

      def to_json(options = {})
        hash = to_hash
        hash.delete('_id')
        hash.delete('hashed_password')
        hash['groups']&.collect!{ |g| g.to_s }
        hash.to_json(options)
      end

    end
  end
end
