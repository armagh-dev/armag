# Copyright 2016 Noragh Analytics, Inc.
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

gem 'mongo', '~> 2.1'
require 'mongo'

require 'singleton'
require 'base64'

require_relative '../logging/global_logger'
require_relative '../configuration/file_based_configuration.rb'

module Armagh
  module Connection
    class MongoAdminConnection
      include Singleton

      attr_reader :connection

      def initialize
        Mongo::Logger.logger.level = Logger::WARN
        config = Armagh::Configuration::FileBasedConfiguration.load( self.class.to_s )
        required = [ 'ip', 'port', 'str', 'db' ]
        unless ( config.keys & required ).length == required.length
          raise "Insufficient connection info for admin connection. Ensure armagh_env.json contains Armagh::Connection::MongoAdminConnection[ #{ (required - config).join(', ')}]."
        end
        begin
          conn_uri = "mongodb://#{Base64.decode64( config['str'] ).strip}@#{config['ip']}:#{config['port']}/#{config_db}"
          @connection = Mongo::Client.new( conn_uri )
        rescue => e
          raise "Unable to establish admin database connection: #{e.message}"
        end
      end
    end
  end
end
