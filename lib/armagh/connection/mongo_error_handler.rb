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

require 'mongo/error'
require 'armagh/documents/errors'

require_relative '../connection'

module Armagh
  module Connection
    def self.convert_mongo_exception(e, natural_key: 'Document')
      unexpected_msg = "An unexpected connection error occurred from #{natural_key}: #{e.message}."
      case e
        when Mongo::Error::MaxBSONSize
          DocumentSizeError.new("#{natural_key} is too large.  Consider using a divider or splitter to break up the document.")
        when Mongo::Error::OperationFailure
          if e.message =~ /^E11000/
            DocumentUniquenessError.new("Unable to create #{natural_key}.  This document already exists.")
          else
            ConnectionError.new(unexpected_msg)
          end
        when Mongo::Error
          ConnectionError.new(unexpected_msg)
        else
          e
      end
    end
  end
end
