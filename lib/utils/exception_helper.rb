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

module Armagh
  module Utils
    class ExceptionHelper
      def self.exception_to_hash(exception, timestamp: true)
        hash = {
            'class' => exception.class.to_s,
            'message' => exception.message,
            'trace' => exception.backtrace,
        }

        hash['timestamp'] = Time.now.utc if timestamp
        hash['cause'] = exception_to_hash(exception.cause, timestamp: false) if exception.cause
        hash
      end

      def self.exception_to_string(exception)
        str = "#{exception.class} => #{exception.message}"
        str << "\n  #{exception.backtrace.join("\n  ")}" if exception.backtrace
        str << "\nCaused By: #{exception_to_string(exception.cause)}" if exception.cause
        str
      end
    end
  end
end