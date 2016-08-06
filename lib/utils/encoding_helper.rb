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

require_relative '../logging'
require_relative '../errors'

require 'singleton'

module Armagh
  module Utils
    class EncodingHelper
      def self.fix_encoding(object, proposed_encoding: nil, logger: nil)
        # Strings, Hashes, and Arrays are the only supported BSON types that would require encoding
        if object.is_a? String
          return fix_string_encoding(object, proposed_encoding: proposed_encoding, logger: logger)
        elsif object.is_a? Hash
          return fix_hash_encoding(object, proposed_encoding: proposed_encoding, logger: logger)
        elsif object.is_a? Array
          return fix_array_encoding(object, proposed_encoding: proposed_encoding, logger: logger)
        else
          return object
        end
      end

      private_class_method def self.fix_hash_encoding(hash, proposed_encoding: nil, logger: nil)
        hash = hash.dup if hash.frozen?
        hash.each do |key, value|
          hash[key] = fix_encoding(value, proposed_encoding: proposed_encoding, logger: logger)
        end
        return hash
      end

      private_class_method def self.fix_array_encoding(array, proposed_encoding: nil, logger: nil)
        array = array.dup if array.frozen?
        array.map! do |value|
          fix_encoding(value, proposed_encoding: proposed_encoding, logger: logger)
        end
        return array
      end

      private_class_method def self.fix_string_encoding(string, proposed_encoding: nil, logger: nil)
        return string if string.encoding == TARGET_ENCODING && string.valid_encoding?

        string = string.dup if string.frozen?

        proposed_encodings = [string.encoding]

        if proposed_encoding
          begin
            proposed_encoding_const = Encoding.find(proposed_encoding)
            proposed_encodings << proposed_encoding_const unless proposed_encoding_const == string.encoding
          rescue
            logger.ops_warn("Unknown encodings #{proposed_encoding}.  Available encodings are #{Encoding.name_list.sort.join(', ')}.") if logger
          end
        end

        encodings = (proposed_encodings | ALTERNATE_ENCODINGS)

        encodings.each do |encoding|
          begin
            string.force_encoding(encoding) unless string.encoding == encoding

            if string.valid_encoding?
              string.encode!(TARGET_ENCODING)
              return string
            end
          rescue
            # Attempted encoding failed.  Keep trying
          end
        end

        logger.ops_warn "Unable to determine source encoding.  Forcing to #{TARGET_ENCODING.name} in a possibly destructive manner." if logger
        string = string.force_encoding(Encoding::BINARY).encode(TARGET_ENCODING, :invalid => :replace, :undef => :replace, :replace => ' ')
        string
      rescue => e
        Armagh::Logging.ops_error_exception(logger, e, "Unable to encode string.  Forcing to #{TARGET_ENCODING.name} in a possibly destructive manner.") if logger
        string = string.force_encoding(Encoding::BINARY).encode(TARGET_ENCODING, :invalid => :replace, :undef => :replace, :replace => ' ')
        string
      end

      private_class_method def self.get_target_encoding
        target_encoding = ENV['ARMAGH_ENCODING'] || FALLBACK_ENCODING
        encoding = Encoding.find(target_encoding)
        Encoding.default_internal = encoding
        Encoding.default_external = encoding
        encoding
      rescue
        raise Errors::EncodingError, "Unable to set encoding to '#{ENV['ARMAGH_ENCODING']}', which came from the ARMAGH_ENCODING env variable.  Available encodings are #{Encoding.name_list.sort.join(', ')}."
      end

      private_class_method def self.load_encodings
        # Taken from https://w3techs.com/technologies/overview/character_encoding/all in order (August 2016)
        encodings = []
        encodings << Encoding::UTF_8        if defined? Encoding::UTF_8
        encodings << Encoding::ISO8859_1    if defined? Encoding::ISO8859_1
        encodings << Encoding::WINDOWS_1251 if defined? Encoding::WINDOWS_1251
        encodings << Encoding::SHIFT_JIS    if defined? Encoding::SHIFT_JIS
        encodings << Encoding::WINDOWS_1252 if defined? Encoding::WINDOWS_1252
        encodings << Encoding::GB2312       if defined? Encoding::GB2312
        encodings << Encoding::EUC_KR       if defined? Encoding::EUC_KR
        encodings << Encoding::EUC_JP       if defined? Encoding::EUC_JP
        encodings << Encoding::GBK          if defined? Encoding::GBK
        encodings << Encoding::ISO_8859_2   if defined? Encoding::ISO_8859_2
        encodings << Encoding::WINDOWS_1250 if defined? Encoding::WINDOWS_1250
        encodings << Encoding::ISO_8859_15  if defined? Encoding::ISO_8859_15
        encodings << Encoding::WINDOWS_1256 if defined? Encoding::WINDOWS_1256
        encodings << Encoding::ISO_8859_9   if defined? Encoding::ISO_8859_9
        encodings << Encoding::BIG5         if defined? Encoding::BIG5
        encodings << Encoding::WINDOWS_1254 if defined? Encoding::WINDOWS_1254
        encodings << Encoding::WINDOWS_874  if defined? Encoding::WINDOWS_874
        (encodings | Encoding.list).freeze
                           end

      FALLBACK_ENCODING = Encoding::UTF_8
      TARGET_ENCODING = get_target_encoding
      ALTERNATE_ENCODINGS = load_encodings
    end
  end
end