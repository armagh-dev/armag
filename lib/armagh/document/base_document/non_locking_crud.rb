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

require_relative 'content_cleanup'
require_relative '../../connection/mongo_error_handler'
require 'armagh/documents/errors'

module Armagh
  module BaseDocument


    module NonLockingCRUD

      # NonLockingCRUD module provides the basic CRUD operations for
      # instantiated BaseDocument objects.  It does not provide direct-to-database
      # CRUD operations, e.g., update_many or delete_many, which change the database
      # but do not return new or updated instantiated objects.
      #
      # The BaseDocument class includes this module by default.  To get locking behavior
      # instead, include Armagh::BaseDocument::LockingCRUD in your BaseDocument child class.
      #
      # WARNING!  Using non-locking CRUD operations provides no protection from
      # having the document your working on being changed out from under you in the DB
      # while you're doing your processing.  There is no warning provided if this happens
      # at any point in the object lifecycle.  If you need safe behavior, use LockingCRUD.
      #

      module ClassMethods

        def create_one(values, collection: self.default_collection)
          new( values, collection:collection ).save
        end

        def upsert_one( qualifier, values, collection: self.default_collection )
          new( values, collection: collection ).save( with_qualifier: qualifier )
        end

        def find_or_create_one(qualifier, values, collection: self.default_collection)
          find_one( qualifier, collection: collection ) || create_one( values, collection: collection )
        end

        def find_many(qualifier, collection: self.default_collection)
          images = collection.find(qualifier)
          images.to_a.compact.collect{ |image| new( image, collection: collection )}
        end

        def find_one(qualifier, collection: self.default_collection)
          begin
            image = collection.find(qualifier).limit(1).first
            new( image, collection: collection ) if image
          rescue => e
            raise Armagh::Connection.convert_mongo_exception( e )
          end
        end

        def find_one_by_internal_id(internal_id, collection: self.default_collection)
         find_one( { '_id' => bsonize_internal_id(internal_id) }, collection: collection )
        end
        alias_method :get, :find_one_by_internal_id

        def find_one_by_document_id( document_id, collection: self.default_collection)
          find_one( { 'document_id' => document_id}, collection: collection )
        end

        def find_one_image_by_internal_id( internal_id, collection: self.default_collection)
          begin
            collection.find({'_id' => bsonize_internal_id(internal_id)}).limit(1).first
          rescue => e
            raise Armagh::Connection.convert_mongo_exception( e )
          end
        end

        def delete( qualifier, collection: self.default_collection )
          begin
            collection.delete_one( qualifier )
          rescue => e
            raise Armagh::Connection.convert_mongo_exception( e )
          end
        end

        def bsonize_internal_id( internal_id )
          use_internal_id = internal_id.dup
          begin
            use_internal_id = BSON.ObjectId( use_internal_id )
          rescue
          end
          use_internal_id
        end

      end


      # Saves the current document.
      #
      # You can change the collection in which the document is saved by specifying in_collection.  The
      # version of the document in the old collection is deleted.
      #
      # If you are changing the collection, and in the process are replacing a document in that target
      # collection, you can specify with_internal_id to ensure the document in the target directly retains
      # its internal_id.
      #
      # If you are replacing a document in the target collection, you must set replacing: true. Otherwise
      # this method will attempt an insert and fail.
      #
      # If you want to save the document without changing its update_timestamp, set update_timestamps: false.
      #
      def save( update_timestamps: true, with_internal_id: nil, with_qualifier: nil, in_collection: nil, replacing: nil )

        begin
          original_internal_id = @image[ '_id' ]
          target_internal_id = with_internal_id || original_internal_id

          qualifier = with_qualifier ? with_qualifier : (target_internal_id ? { '_id' => target_internal_id } : nil )
          original_collection = @_collection
          target_collection = in_collection || original_collection
          changing_collections = ( target_collection != original_collection )

          original_timestamps = set_timestamps   if update_timestamps

          save_content = ContentCleanup.clean_image( @image )


          if qualifier && (replacing || !changing_collections)
            result = target_collection.replace_one( qualifier, @image, upsert: true )
            @image[ '_id' ] ||= result.upserted_id
            @_collection = target_collection
          else
            @image['_id'] = target_collection.insert_one( save_content ).inserted_ids.first
            @_collection = target_collection
          end
          if changing_collections && original_internal_id
            result = original_collection.delete_one({'_id' => original_internal_id })
            raise Connection::ConnectionError, "Unable to delete #{ natural_key } from #{@_collection_last_saved.name}" unless result.deleted_count == 1
          end
        rescue => e
          set_timestamps( original_timestamps ) if original_timestamps && update_timestamps
          raise Armagh::Connection.convert_mongo_exception( e )
        end
        self
      end

      # Deletes the current document from the database and sets the internal_id of the
      # current document object to nil. Be sure not to reuse this object.
      def delete
        deleting_from_collection = @_collection
        deleting_from_collection.delete_one( { '_id' => internal_id } )
        @image[ '_id' ] = nil
        nil
      rescue => e
        raise Armagh::Connection.convert_mongo_exception( e )
      end

      def refresh
        @_shadow = {}
        reset_image( self.class.find_one_image_by_internal_id( internal_id ))
      end

      def self.included( base )
        base.extend ClassMethods
      end
    end
  end
end
