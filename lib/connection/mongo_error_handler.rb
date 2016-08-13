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

require 'mongo/error'
require 'armagh/documents/errors'

module Armagh
  module Connection
    def self.convert_mongo_exception(e, id = nil)
      if id
        unexpected_msg = "An unexpected connection error occurred from document #{id}: #{e.message}."
      else
        unexpected_msg = "An unexpected connection error occurred: #{e.message}."
      end
      case e
        when Mongo::Error::MaxBSONSize
          Documents::Errors::DocumentSizeError.new("Document #{id} is too large.  Consider using a divider or splitter to break up the document.")
        when Mongo::Error::OperationFailure
          if e.message =~ /^E11000/
            Documents::Errors::DocumentUniquenessError.new("Unable to create document #{id}.  This document already exists.")
          else
            Errors::ConnectionError.new(unexpected_msg)
          end
        when Mongo::Error
          Errors::ConnectionError.new(unexpected_msg)
        else
          e
      end
    end
  end
end
