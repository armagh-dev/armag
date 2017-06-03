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

require 'argon2'
require 'base64'
require 'set'

require 'armagh/support/random'

module Armagh
  module Utils
    module Password
      class PasswordError < StandardError; end

      MIN_PWD_LENGTH = 8 # TODO Make this configurable
      BAD_PASSWORD_FILES = File.join(__dir__, '..', '..', 'config', 'common_passwords.b64')

      def self.hash(password)
        Argon2::Password.create(password)
      end

      def self.verify_strength(password)
        raise PasswordError, 'Password must be a string.' unless password.is_a? String
        raise PasswordError, "Password must contain at least #{MIN_PWD_LENGTH} characters." if password.length < MIN_PWD_LENGTH
        raise PasswordError, 'Password is a common password.' if common? password
        true
      end

      def self.common?(password)
        #https://github.com/danielmiessler/SecLists/blob/master/Passwords/10_million_password_list_top_10000.txt
        @common_passwords ||= Set.new Base64.decode64(File.read(BAD_PASSWORD_FILES)).split("\n")
        @common_passwords.include? password # Faster than using an Array
      end

      def self.correct?(password, hash)
        Argon2::Password.verify_password(password, hash)
      end

      def self.random_password
        Support::Random.random_str MIN_PWD_LENGTH
      end
    end
  end
end