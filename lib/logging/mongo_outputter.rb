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

require 'log4r/outputter/outputter'
require 'socket'

require_relative '../connection'

module Log4r
  class MongoOutputter < Log4r::Outputter
    def initialize(_name, hash={})
      super
      @resource_log = hash['resource_log']
    end

    def write(data)
      raise ArgumentError, 'Data must be a hash.' unless data.is_a? Hash

      if @resource_log
        Armagh::Connection.resource_log.insert_one data
      else
        Armagh::Connection.log.insert_one data
      end
    rescue => e
      raise Armagh::Connection.convert_mongo_exception(e)
    end
  end
end