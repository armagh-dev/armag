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

require 'logger'
require_relative 'multi_io'

module Armagh
  module Logging
    class GlobalLogger < Logger
      require 'socket'
      require_relative '../connection'
      
      attr_accessor :is_a_resource_log

      LEVEL_LOOKUP = %w(DEBUG INFO WARN ERROR FATAL)

      def initialize(component, log_dev = STDOUT, shift_age = 0, shift_size = 1048576)
        dev = LogDevice.new(log_dev, :shift_age => shift_age, :shift_size => shift_size)
        multi_io = MultiIO.new(dev, STDOUT)

        super(multi_io, shift_age, shift_size)
        @progname = component
        @hostname = Socket.gethostname
        
        @is_a_resource_log = false
        
      end

      def add(severity, message = nil, progname = nil, &block)
        if severity >= @level
          if message.nil?
            if block_given?
              message = yield
            else
              message = progname
            end
          end

          super(severity, message, nil)
          add_global(severity, message)
        end
      end

      def add_global(severity, message)
        log_msg = {
            'component' => @progname,
            'hostname' => @hostname,
            'pid' => $$,
            'level' => format_severity(severity),
            'timestamp' => Time.now
        }

        if message.is_a? Exception
          log_msg['exception'] = {
              'message' => message.inspect,
              'trace' => message.backtrace
          }
        else
          log_msg['message'] = message
        end

        if @is_a_resource_log
          Connection.resource_log.insert_one log_msg
        else
          Connection.log.insert_one log_msg
        end
      end
    end
  end
end
