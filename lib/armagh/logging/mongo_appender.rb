# Copyright 2018 Noragh Analytics, Inc.
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

require 'logging/appender'
require 'socket'

require_relative '../connection'

module Armagh
  module Logging
    def self.mongo(*args)
      MongoAppender.new(*args)
    end

    class MongoAppender < ::Logging::Appender
      def initialize(name, opts = {})
        super(name, opts)
        @hostname = Socket.gethostname
        @name = name
        @resource_log = opts['resource_log']
        @alert_level = opts['alert_level']
      end

      def write(event)
        log_msg = {
          'component' => event.logger,
          'hostname' => @hostname,
          'pid' => $$,
          'level' => Armagh::Logging::LEVELS[event.level],
          'timestamp' => event.time.dup.utc
        }

        log_msg[ 'alert' ] = true if Armagh::Logging::ALERT_LEVELS.include?(event.level)

        workflow = ::Logging.mdc['workflow']
        action = ::Logging.mdc['action']
        action_supertype = ::Logging.mdc['action_supertype']
        document_internal_id = ::Logging.mdc['document_internal_id']

        log_msg['workflow'] = workflow if workflow
        log_msg['action'] = action if action
        log_msg['action_supertype'] = action_supertype if action_supertype
        log_msg['document_internal_id'] = document_internal_id if document_internal_id

        if event.data.is_a? Armagh::Logging::EnhancedException
          log_msg['message'] = "#{event.data.additional_details}"
          log_msg['exception'] = Armagh::Utils::ExceptionHelper.exception_to_hash(event.data.exception, timestamp: false)
        elsif event.data.is_a? Exception
          log_msg['exception'] = Armagh::Utils::ExceptionHelper.exception_to_hash(event.data, timestamp: false)
        else
          log_msg['message'] = "#{event.data}"
        end

        # don't set collection in initialize because the loggers wont be set up yet
        @collection ||= @resource_log ? Armagh::Connection.resource_log : Armagh::Connection.log
        @collection.insert_one log_msg
      rescue => e
        $stderr.puts e.inspect, e.backtrace.join("\n\t")
      end
    end
  end
end