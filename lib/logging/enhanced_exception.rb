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

module Armagh
  module Logging
    class EnhancedException
      attr_accessor :additional_details, :exception

      def initialize(additional_details, exception)
        @additional_details = additional_details
        @exception = exception
      end

      def to_s
        str = "#{@additional_details}: #{@exception.to_s}"
        str << "\n  #{@exception.backtrace.join("\n  ")}" if @exception.backtrace
        str
      end

      def inspect
        "#{@additional_details}: #{@exception.inspect}"
      end
    end
  end
end
