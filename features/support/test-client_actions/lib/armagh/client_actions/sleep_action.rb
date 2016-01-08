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

require 'armagh/action'

module Armagh
  module ClientActions

    class SleepAction < Armagh::Action
      def execute(doc_content, doc_meta)
        @logger.info 'Sleep action is sleeping for 2 seconds'
        sleep 2
        insert_document('complete', nil)
        @logger.info 'Sleep action is done sleeping'
      end
    end
  end
end
