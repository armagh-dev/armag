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

require 'facets/kernel/deep_copy'

module Armagh
  module Connection
    class DBDoc
      def self.default_collection
        nil
      end

      attr_reader :db_doc

      class << self
        protected :new
      end

      def initialize(image = {})
        @db_doc = image
        Utils::DBDocHelper.restore_model(self)
      end

      # Creates accessor methods that get/set key-value pairs in the hidden hash image for the document.
      # If your value is an array, you get more helper methods by using delegated_attr_accessor_array.
      #
      # @param method [String or Symbol] the method name, e.g., editor, creates method editor and self.editor=
      # @param key [String or Symbol] optional hash key if different from the method name
      # @param validates_with [Symbol] optional method you define that takes value and validates / returns it before storage
      # @param after_change [Symbol] optional method you define that takes value and carries out clean up actions needed after value change
      # @param after_return [Symbol] optional method you define that takes retrieved value and performs additional operations before returning
      #
      # Accessor methods created for delegated_attr_accessor :editor include:
      #
      #    editor
      #    self.editor=      you need self to prevent ruby from interpreting editor as a local variable
      #    delete_editor     removes editor key from the hidden document hash
      #
      # Examples:
      #   delegated_attr_accessor :timestamp, validates_with :cast_as_time, after_return: :get_utc
      #   delegated_attr_accessor :very_long_useful_method_name, :vlumn
      #   delegated_attr_accessor :account_balance, after_change: set_broke_on_zero
      #
      def self.delegated_attr_accessor( method, key=nil, validates_with: nil, after_change: nil, after_return: nil )
        use_key = (key||method).to_s
        define_method( method.to_s ) {
          result = @db_doc[ use_key ]
          after_return ? send( after_return, result ) : result
        }
        define_method( "#{method}=" ) { |value|
          validated_value = value.deep_copy
          validated_value = send( validates_with, validated_value ) if validates_with
          @db_doc[ use_key ] = validated_value
          send( after_change, validated_value ) if after_change
        }
        define_method( "delete_#{method}" ){
          @db_doc.delete( use_key )
          send( after_change, nil ) if after_change
        }
      end

      # Creates acccessor methods that get/set key-value pairs in the hidden hash image for the document, where the value is an array.
      #
      # @param method [String or Symbol] the method name that is inherently plural, e.g., editors or gentlemen
      # @param key [String or Symbol] optional hash key if different from the method name
      # @param validates_each_with [Symbol] optional method you define that takes item value and validates / returns it before storage
      # @param after_change [Symbol] optional method you define that takes array and carries out clean up actions needed after value change
      # @param after_return [Symbol] optional method you define that takes retrieved array and performs additional operations before returning
      #
      # Accessor methods created for delegated_attr_accessor_array :editors include:
      #
      #    editors
      #    add_items_to_editors( array_of_editors )
      #    add_item_to_editors( editor )
      #    remove_item_from_editors( editor )
      #    delete_editors          removes the editors key from the hidden document hash.
      #
      # Examples:
      #   delegated_attr_accessor_array :split_times, validates_with :cast_as_time, after_return: :get_utc
      #
      def self.delegated_attr_accessor_array( method, key=nil, singular: nil, validates_each_with: nil, after_change: nil, after_return: nil )
        use_key = (key || method).to_s

        define_method( method.to_s ) {
          result = @db_doc[ use_key ]
          after_return ? send( after_return, result ) : result
        }
        define_method( "add_items_to_#{method}") { |array_of_values|
          validated_array = (array_of_values.deep_copy || []).flatten.compact
          validated_array.collect!{ |item| send( validates_each_with, item ) } if validates_each_with
          @db_doc[ use_key ] ||= []
          @db_doc[ use_key ].concat( validated_array )
          send( after_change, @db_doc[ use_key ] ) if after_change
        }
        define_method( "add_item_to_#{method}" ) { |value|
          validated_value = value.deep_copy
          validated_value = send( validates_each_with, validated_value ) if validates_each_with
          @db_doc[ use_key ] ||= []
          @db_doc[ use_key ] << validated_value
          send( after_change, @db_doc[ use_key ] ) if after_change
        }
        define_method( "remove_item_from_#{method}") { |value|
          @db_doc[ use_key ] ||= []
          @db_doc[ use_key ].delete( value )
          send( after_change, @db_doc[ use_key ] ) if after_change
        }
        define_method( "clear_#{method}") {
          @db_doc[ use_key ] ||= []
          @db_doc[ use_key ].clear
          send( after_change, @db_doc[ use_key ] ) if after_change
        }
        define_method( "delete_#{method}") {
          @db_doc.delete( use_key )
          send( after_change, nil ) if after_change
        }
      end


      # Creates acccessor methods that get/set errors in the hidden hash image for the document.
      # Errors are a special case for db_doc.  An error accessor is a hash of arrays, e.g., these_errors[ category ] = [ error1, error2 ]
      #
      # @param method [String or Symbol] the method name that is inherently plural, e.g., editors or gentlemen
      # @param key [String or Symbol] optional hash key if different from the method name
      # @param after_change [Symbol] optional method you define that takes the errors and carries out clean up actions needed after value change
      #
      # Accessor methods created for delegated_attr_accessor_errors :dev_errors include:
      #
      #    dev_errors
      #    add_error_to_dev_errors( category, error )
      #    remove_error_from_dev_errors( category )
      #    clear_dev_errors
      #
      # Example:
      #   delegated_attr_accessor_errors :dev_errors
      #
      def self.delegated_attr_accessor_errors( method, key=nil, after_change: nil )
        use_key = (key||method).to_s

        define_method( method.to_s ) {
          @db_doc[ use_key ]
        }
        define_method( "add_error_to_#{method}" ) { |action_name, details|
          @db_doc[ use_key ] ||= {}
          @db_doc[ use_key ][ action_name ] ||= []
          if details.is_a?(Exception)
            @db_doc[ use_key ][action_name] << Utils::ExceptionHelper.exception_to_hash(details)
          else
            @db_doc[ use_key ][action_name] << { 'message' => details.to_s, 'timestamp' => Time.now.utc}
          end
          send( after_change, @db_doc[ use_key ] ) if after_change
        }

        define_method( "remove_error_from_#{method}" ) { |action|
          @db_doc[ use_key ]&.delete(action)
          send( after_change, @db_doc[ use_key ] ) if after_change
        }

        define_method( "clear_#{method}" ){
          @db_doc[ use_key ]&.clear
          send( after_change, nil ) if after_change
        }

      end
      
      delegated_attr_accessor 'internal_id', '_id'
      delegated_attr_accessor 'updated_timestamp', after_return: :get_ts_utc
      delegated_attr_accessor 'created_timestamp', after_return: :get_ts_utc

      def get_ts_utc( ts )
        ts&.utc
      end

      def mark_timestamp
        now = Time.now
        self.updated_timestamp = now
        self.created_timestamp ||= now
      end

      def self.db_create(values, collection = self.default_collection)
        check_collection(collection)
        collection.insert_one(values).inserted_ids.first
      end

      def self.db_find_one(qualifier, collection = self.default_collection)
        db_find(qualifier, collection).limit(1).first
      end

      def self.db_find(qualifier, collection = self.default_collection)
        check_collection(collection)
        collection.find(qualifier)
      end

      def self.db_find_and_update(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.find_one_and_update(qualifier, {'$set': values}, {return_document: :after, upsert: true})
      end

      def self.db_update(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.update_one(qualifier, {'$setOnInsert': values}, {upsert: true})
      end

      def self.db_replace(qualifier, values, collection = self.default_collection)
        check_collection(collection)
        collection.replace_one(qualifier, values, {upsert: true})
      end

      def self.db_delete(qualifier, collection = self.default_collection)
        check_collection(collection)
        collection.delete_one(qualifier)
      end

      def fix_encoding( proposed_encoding, logger: nil )
        Armagh::Support::Encoding.fix_encoding(@db_doc, proposed_encoding: proposed_encoding, logger: logger)
      end

      def clean_model
        Armagh::Utils::DBDocHelper.clean_model(self)
      end

      def inspect
        to_hash.inspect
      end

      def to_s
        to_hash.to_s
      end

      def to_hash
        @db_doc.deep_copy
      end

      def to_json(options = {})
        hash = to_hash
        hash['_id'] = hash['_id'].to_s if hash['_id']
        hash.to_json(options)
      end

      def self.check_collection(collection)
        raise ArgumentError, 'No collection specified.  Make sure <model>.default_collection is defined.' unless collection
      end
    end
  end
end
