gem 'mongo', '~> 2.1'
require 'mongo'

require 'singleton'
require 'base64'

require_relative '../logging/global_logger'

module Armagh
  module Connection
    class MongoAdminConnection
      include Singleton

      attr_reader :connection

      def initialize
        Mongo::Logger.logger.level = Logger::WARN
        unless ENV[ 'ARMAGH_STRF' ]
          raise "No admin connection string defined.  Aborting. Define a base-64 encoded mongo connection URI in env variable ARMAGH_STRF."
        end
        begin
          con_str = Base64.decode64( ENV[ 'ARMAGH_STRF' ]).strip
          @connection = Mongo::Client.new( con_str )
        rescue => e
          raise "Unable to establish admin database connection. #{e.message}"
        end
      end
    end
  end
end
