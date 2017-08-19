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

require_relative 'authentication/configuration'
require_relative 'authentication/directory'
require_relative 'authentication/group'
require_relative 'authentication/role'
require_relative 'authentication/user'

require_relative 'connection'

module Armagh
  module Authentication
    class AuthenticationError < StandardError; end

    def self.setup_authentication
      @config = find_or_create_config
      User.setup_default_users
      Group.setup_default_groups
    end

    def self.config
      @config ||= find_or_create_config
    end

    private_class_method def self.find_or_create_config
      Configuration.find_or_create_configuration( Connection.config, Configuration::CONFIG_NAME, values_for_create: {}, maintain_history: true )
    end
  end
end