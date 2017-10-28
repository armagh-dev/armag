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

require 'armagh/support/encoding'

module Armagh
  module BaseDocument
    module ContentCleanup

      DOT_REPLACEMENT = '~!p!~'
      DOLLAR_REPLACEMENT = '~!d!~'

      def self.clean_image( image )
        clean_hash( image )
      end

      def self.restore_image( image )
        restore_hash( image )
      end

      private_class_method
      def self.clean(object)
        case object
        when String
          clean_string object
        when Hash
          clean_hash object
        when Array
          clean_array object
        else
          object
        end
      end

      private_class_method def self.clean_hash(hash)
        hash.keys.each do |k|
          v = hash[k]
          clean(v)
          if v.nil?
            hash.delete(k)
          elsif k =~ /[.$]/
            hash.delete(k)
            hash[k.gsub('.', DOT_REPLACEMENT).gsub('$', DOLLAR_REPLACEMENT)] = v
          end
        end
        hash
      end

      private_class_method def self.clean_string(string)
        string.strip! unless string.frozen?
      end

      private_class_method def self.clean_array(array)
        array.each{|v| clean(v)}
      end

      private_class_method def self.restore(object)
        case object
        when Hash
          restore_hash object
        when Array
          restore_array object
        else
          object
        end
      end

      private_class_method def self.restore_hash(hash)
        hash.keys.each do |k|
          v = hash[k]
          restore(v)
          if k =~ /(#{DOT_REPLACEMENT}|#{DOLLAR_REPLACEMENT})/
            hash.delete(k)
            hash[k.gsub(DOT_REPLACEMENT, '.').gsub(DOLLAR_REPLACEMENT, '$')] = v
          end
        end
        hash
      end

      def self.restore_array(array)
        array.each{|v| restore(v)}
      end

      def self.fix_encoding( proposed_encoding, target, logger: nil )
        Armagh::Support::Encoding.fix_encoding(target, proposed_encoding: proposed_encoding, logger: logger || @logger)
      end

    end
  end
end
