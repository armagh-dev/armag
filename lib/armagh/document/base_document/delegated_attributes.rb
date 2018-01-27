# Copyright 2018 Noragh Analytics, Inc.
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
require_relative '../../utils/exception_helper'

module Armagh
  module BaseDocument
    module DelegatedAttributes

      module ClassMethods

        # Creates accessor methods that get/set key-value pairs in the hidden hash image for the document.
        # If your value is an array, you get more helper methods by using delegated_attr_accessor_array.
        #
        # @param method [String or Symbol] the method name, e.g., editor, creates method editor and self.editor=
        # @param key [String or Symbol] optional hash key if different from the method name
        # @param validates_with [Symbol] optional method you define that takes value and validates / returns it before storage
        # @param after_change [Symbol] optional method you define that takes value and carries out clean up actions needed after value change
        # @param after_return [Symbol] optional method you define that takes retrieved value and performs additional operations before returning
        # @param delegates_to [Symbol] optional ivar symbol you provide to override the default delegation to :@image
        # @param references_class [Class] optional facade method that returns the references_class Document whose internal_id is the value.
        #
        # Note that references_class is a convenience method with limited scope.  No actions cascade to referenced documents,
        # so ensure your application code provides whatever sync is necessary.
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
        #   delegated_attr_accessor :account_internal_ids, references_class: AccountDocument
        #
        def delegated_attr_accessor( method, key=nil, validates_with: nil, after_change: nil, after_return: nil, delegates_to: :@image, references_class: nil )
          use_key = (key||method).to_s

          define_method( method.to_s ) {
            result = instance_variable_get(delegates_to)[ use_key ]
            result = load_to_shadow( use_key, result, references_class ) if references_class
            after_return ? send( after_return, result ) : result
          }
          define_method( "#{method}=" ) { |value|
            validated_value = nil
            begin
              validated_value = (references_class and value.is_a?(references_class )) ? value.internal_id : value.deep_copy
            rescue => e
              raise TypeError, "Can't save an object in #{method}; did you forget to specify references_class?" if /dump/=~e.message
              raise e
            end
            validated_value = send( validates_with, validated_value ) if validates_with

            instance_variable_get(delegates_to)[ use_key ] = validated_value
            load_to_shadow( use_key, validated_value, references_class, use_object: value ) if (references_class && value.is_a?(references_class))
            send( after_change, validated_value ) if after_change
          }
          define_method( "delete_#{method}" ){
            instance_variable_get(delegates_to).delete( use_key )
            clear_from_shadow( use_key ) if references_class
            send( after_change, nil ) if after_change
          }
        end

        # Creates accessor methods that get/set key-value pairs in the hidden hash image for the document, where the value is an array.
        #
        # @param method [String or Symbol] the method name that is inherently plural, e.g., editors or gentlemen
        # @param key [String or Symbol] optional hash key if different from the method name
        # @param validates_each_with [Symbol] optional method you define that takes item value and validates / returns it before storage
        # @param after_change [Symbol] optional method you define that takes array and carries out clean up actions needed after value change
        # @param after_return [Symbol] optional method you define that takes retrieved array and performs additional operations before returning
        # @param delegates_to [Symbol] optional ivar symbol you provide to override the default delegation to :@image
        # @param references_class [Class] optional facade method that returns the references_class Document whose internal_id is each item value.
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
        def delegated_attr_accessor_array( method, key=nil, validates_each_with: nil, after_change: nil, after_return: nil, delegates_to: :@image, references_class: nil  )
          use_key = (key || method).to_s

          define_method( method.to_s ) {
            result = instance_variable_get(delegates_to)[ use_key ]
            result = send( "clear_#{method}") if result.nil?
            result = result.collect{ |item| load_to_shadow( use_key, item, references_class )} if references_class
            after_return ? send( after_return, result ) : result
          }

          define_method( "#{method}="){ |array_of_values|
            send( "clear_#{method}")
            send( "add_items_to_#{method}", array_of_values)
          }

          define_method( "add_items_to_#{method}") { |array_of_values|
            array_of_values&.each do |value|
              send("add_item_to_#{method}", value, suppress_after_change: true )
            end
            image = instance_variable_get(delegates_to)
            after_change ? send( after_change, image[ use_key ] ) : image[use_key]
          }

          define_method( "add_item_to_#{method}" ) { |value,suppress_after_change: false|
            image = instance_variable_get(delegates_to)
            validated_value = nil
            begin
              validated_value = (references_class && value.is_a?(references_class)) ? value.internal_id : value.deep_copy
            rescue => e
              raise TypeError, "Can't save an object in #{method}; did you forget to specify references_class?" if /dump/=~e.message
              raise e
            end

            validated_value = send( validates_each_with, validated_value ) if validates_each_with
            image[ use_key ] ||= []
            image[ use_key ] << validated_value
            load_to_shadow( use_key, validated_value, references_class, use_object: value ) if (references_class && value.is_a?(references_class))
            (after_change && !suppress_after_change )? send( after_change, image[use_key] ) : image[ use_key ]
          }
          define_method( "remove_item_from_#{method}") { |value|
            image = instance_variable_get(delegates_to)
            image[ use_key ] ||= []
            remove_value = value
            remove_value = get_internal_id_and_remove_shadow( use_key, remove_value ) if references_class
            image[ use_key ].delete( remove_value )
            after_change ? send( after_change, image[use_key] ) : image[ use_key ]
          }
          define_method( "clear_#{method}") {
            image = instance_variable_get(delegates_to)
            image[ use_key ] ||= []
            image[ use_key ].clear
            clear_from_shadow( use_key ) if references_class
            after_change ? send( after_change, image[use_key] ) : image[ use_key ]
          }
          define_method( "delete_#{method}") {
            instance_variable_get(delegates_to).delete( use_key )
            clear_from_shadow( use_key ) if references_class
            after_change ? send( after_change, image[use_key] ) : image[ use_key ]
          }
          define_method( "delete_#{method}_if" ) { |&block|
            image = instance_variable_get(delegates_to)
            image[use_key] ||= []
            num_items_before_delete = image[use_key].length
            image[use_key].delete_if &block
            after_change && (num_items_before_delete > image[use_key].length) ? send( after_change, image[use_key] ) : image[ use_key ]
          }
        end

        # Creates acccessor methods that get/set errors in the hidden hash image for the document.
        # Errors are a special case for db_doc.  An error accessor is a hash of arrays, e.g., these_errors[ category ] = [ error1, error2 ]
        #
        # @param method [String or Symbol] the method name that is inherently plural, e.g., editors or gentlemen
        # @param key [String or Symbol] optional hash key if different from the method name
        # @param after_change [Symbol] optional method you define that takes the errors and carries out clean up actions needed after value change
        # @param delegates_to [Symbol] optional ivar symbol you provide to override the default delegation to :@image
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
        def delegated_attr_accessor_errors( method, key=nil, after_change: nil, delegates_to: :@image )
          use_key = (key||method).to_s

          define_method( method.to_s ) {
            image = instance_variable_get(delegates_to)
            image[ use_key ] = {} if image[ use_key].nil?
            image[use_key]
          }

          define_method( "#{method}=") { |errors_hash|
            errors_hash.each do |action_name, errors |
              errors.each do |error|
                send "add_error_to_#{method}", action_name, error
              end
            end
          }

          define_method( "add_error_to_#{method}" ) { |action_name, details|
            image = instance_variable_get(delegates_to)
            image[ use_key ] ||= {}
            image[ use_key ][ action_name ] ||= []
            if details.is_a?(Exception)
              image[ use_key ][action_name] << Utils::ExceptionHelper.exception_to_hash(details)
            else
              image[ use_key ][action_name] << { 'message' => details.to_s, 'timestamp' => Time.now.utc}
            end
            after_change ? send( after_change, image[ use_key ] ) : image[use_key]
          }

          define_method( "remove_action_from_#{method}" ) { |action|
            instance_variable_get(delegates_to)[ use_key ]&.delete(action)
            send( after_change, instance_variable_get(delegates_to)[ use_key ] ) if after_change
          }

          define_method( "clear_#{method}" ){
            image = instance_variable_get(delegates_to)
            image[ use_key ] ||= {}
            image[ use_key ].clear
            after_change ? send( after_change, image[use_key] ) : image[use_key]
          }

        end
      end

      private def load_to_shadow( use_key, internal_id, referenced_class, use_object: nil )
        @_shadow ||= {}
        @_shadow[ use_key ] ||= {}
        @_shadow[ use_key ][ internal_id ] ||= ( use_object || referenced_class.get( internal_id ))
      end

      private def clear_from_shadow( use_key )
        @_shadow&.[](use_key)&.clear
      end

      private def get_internal_id_and_remove_shadow( use_key, item )
        if item.is_a? Integer
          return_id = item
          @_shadow&.[]( use_key )&.delete return_id
        else
          return_id = item.internal_id
          @_shadow&.[]( use_key )&.delete return_id
        end
        return_id
      end

      def self.included( base )
        base.extend( ClassMethods )
      end
    end
  end
end