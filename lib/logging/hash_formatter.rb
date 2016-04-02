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

require 'log4r/formatter/formatter'
require 'socket'

require_relative '../utils/exception_helper'

module Log4r
  class HashFormatter < Log4r::Formatter
    def initialize(hash={})
      super
      @hostname = Socket.gethostname
    end

    def format(event)
      log_msg = {
          'component' => event.name,
          'hostname' => @hostname,
          'pid' => $$,
          'level' => Log4r::LNAMES[event.level],
          'timestamp' => Time.now
      }

      log_msg['trace'] = event.tracer if event.tracer

      if event.data.is_a? Exception
        log_msg['exception'] = Armagh::Utils::ExceptionHelper.exception_to_hash event.data
      else
        log_msg['message'] = "#{event.data}"
      end

      log_msg
    end
  end
end
