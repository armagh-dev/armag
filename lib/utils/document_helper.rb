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
  module Utils
    class DocumentHelper
      def self.clean_document(doc)
        clean_hash(doc.db_doc)
      end

      private_class_method def self.clean(object)
        if object.is_a? String
          return clean_string(object)
        elsif object.is_a? Hash
          return clean_hash(object)
        elsif object.is_a? Array
          return clean_array(object)
        else
          return object
        end
      end

      private_class_method def self.clean_hash(hash)
        hash.each_value { |v| clean(v) }
      end

      private_class_method def self.clean_string(string)
        string.strip! unless string.frozen?
      end

      private_class_method def self.clean_array(array)
        array.each { |v| clean(v) }
      end
    end
  end
end
