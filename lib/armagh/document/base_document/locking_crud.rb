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

require 'socket'
require_relative 'content_cleanup'
require_relative '../../utils/processing_backoff'
require 'armagh/documents/errors'

module Armagh
  module BaseDocument

    class LockingAgentError < StandardError; end
    class LockTimeoutError < StandardError; end
    class LockExpiredError < StandardError; end
    class ReadOnlyError < StandardError; end

    module LockingCRUD

      # LockingCRUD module provides the locking CRUD operations for
      # instantiated BaseDocument objects.  It does not provide direct-to-database
      # CRUD operations, e.g., update_many or delete_many, which change the database
      # but do not return or update instantiated objects.
      #
      # To get locking behavior, include Armagh::BaseDocument::LockingCRUD in your BaseDocument child class.
      #

      module ClassMethods

        def default_lock_wait_duration=( seconds )
          @lock_wait_duration = seconds
        end

        def default_lock_wait_duration
          @lock_wait_duration || 60
        end

        def default_lock_hold_duration=( seconds )
          @lock_hold_duration = seconds
        end

        def default_lock_hold_duration
          @lock_hold_duration || 60
        end

        def default_locking_agent=( agent )
          @default_locking_agent = agent if valid_locking_agent?( agent )
        end

        def default_locking_agent
          @default_locking_agent
        end

        def with_new_or_existing_locked_document( qualifier,
                                                  values_on_create,
                                                  caller=default_locking_agent,
                                                  collection: self.default_collection,
                                                  lock_wait_duration: default_lock_wait_duration,
                                                  lock_hold_duration: default_lock_hold_duration )
          doc = find_or_create_one_locked( qualifier, values_on_create, caller, collection:collection, lock_wait_duration: lock_wait_duration, lock_hold_duration: lock_hold_duration )
          return false unless doc
          yield doc
          doc.save( true, caller )
          true
        end

        def create_one( *args )
          raise NoMethodError, "Create_one not available in locking documents.  Use create_one_locked or create_one_unlocked."
        end

        def create_one_unlocked(values, collection: self.default_collection, **other_args )
          new( unlocked_values(values), collection:collection, **other_args ).save( true )
        rescue => e
            raise Armagh::Connection.convert_mongo_exception(e)
        end

        def find( *args )
          raise NoMethodError, "Find not available in locking documents.  Use find_many_read_only."
        end

        def find_many_read_only( qualifier, collection:self.default_collection, sort_rule: nil, paging: nil )
          images = collection.find(qualifier)
          images = images.sort(sort_rule) if sort_rule
          images = images.skip( (paging[:page_number]||0) * (paging[:page_size]||20)).limit( paging[:page_size] || 20 ) if paging
          images.collect{ |image| new(image, collection:collection, read_only:true )}
        rescue => e
          raise Armagh::Connection.convert_mongo_exception( e)
        end

        def find_one( *args )
          raise NoMethodError, "Find_one not available in locking documents.  Use find_one_locked or find_one_read_only."
        end

        def find_one_read_only( qualifier, collection: self.default_collection, most_recent: nil )
          image = most_recent ? collection.find( qualifier, { sort: { updated_timestamp: 1 }} ) : collection.find( qualifier )
          image = image.limit(1).first
          new( image, collection: collection, read_only: true ) if image
        rescue => e
          raise Armagh::Connection.convert_mongo_exception( e)
        end

        def find_one_by_internal_id( *args )
          raise NoMethodError, "Find_one_by_internal_id not available in locking documents.  Use find_one_by_internal_locked or find_one_by_internal_id_read_only."
        end

        def get( *args )
          raise NoMethodError, "Get not available in locking documents.  Use get_locked or get_read_only."
        end

        def find_one_by_internal_id_read_only( internal_id, collection: self.default_collection )
          find_one_read_only( { '_id' => internal_id }, collection: collection )
        end
        alias_method :get_read_only, :find_one_by_internal_id_read_only

        def find_one_by_document_id( *args )
          raise NoMethodError, "Find_one_by_document_id not available in locking documents.  Use find_one_by_document_id_locked or find_one_by_document_id_read_only."
        end

        def find_one_by_document_id_read_only( document_id, collection: self.default_collection )
          find_one_read_only( { 'document_id' => document_id}, collection: collection)
        end

        def force_unlock_all_in_collection_held_by( agent, collection: self.default_collection )
          agent_signature = agent.is_a?( String ) ? agent : agent.signature
          collection.update_many(
              { '_locked.by' => agent_signature, '_locked.until' => { '$gt' => Time.now.utc }},
              { '$set' => { '_locked' => false }}
          )
        end

        def force_reset_expired_locks( collection: self.default_collection )
          collection.update_many(
              { '_locked.until' => { '$lt' => Time.now.utc }},
              { '$set' => { '_locked' => false }}
          )
        end

        def interruptible_wait_loop_with_timeout( caller, lock_wait_duration: default_lock_wait_duration )
          backoff = Utils::ProcessingBackoff.new( lock_wait_duration / 2 )
          wait_until = Time.now.utc + lock_wait_duration
          loop do
            yield
            raise LockTimeoutError, "Timed out waiting for document to unlock" if Time.now.utc > wait_until
            backoff.interruptible_backoff{ !caller.running? }
          end
        end

        def valid_locking_agent?( agent )
          return true if agent == @default_locking_agent
          raise( LockingAgentError, "Locking agent must respond to :signature and :running?") unless agent.respond_to?( :signature  ) && agent.respond_to?( :running? )
          true
        end

        def locked_values( values, caller = default_locking_agent, lock_hold_duration: default_lock_hold_duration )
          values.merge({ '_locked' => { 'by' => caller.signature, 'until' => Time.now.utc + lock_hold_duration }}) if valid_locking_agent?(caller)
        end

        def unlocked_values( values )
          values.merge( {'_locked' => false })
        end

        def unlocked_qualifier( qualifier, caller = default_locking_agent )
          { '$and' => [ qualifier, { '_locked' => false }]}
        end

        def unlocked_or_my_qualifier( qualifier, caller = default_locking_agent )
          { '$and' => [ qualifier, { '$or' => [ { '_locked' => false }, { '_locked.by' => caller&.signature }, { '_locked.until' => { '$lt'=> Time.now.utc }}]}] } if valid_locking_agent?(caller)
        end

        def lock_expired_qualifier( qualifier, caller = default_locking_agent )
          { '$and' => [ qualifier, { '$or' => [ { '_locked' => false }, { '_locked.by' => caller&.signature }, { '_locked.until' => { '$lt'=> Time.now.utc }}]}] } if valid_locking_agent?(caller)
        end

        def create_one_locked(values, caller=default_locking_agent, collection: self.default_collection, lock_hold_duration:default_lock_hold_duration )
          new( locked_values(values,caller), collection:collection ).save( false, caller )
        rescue => e
          raise Armagh::Connection.convert_mongo_exception( e)
        end

        def find_or_create_one( *args )
          raise NoMethodError, "Find_or_create_one not available in locking documents.  Use find_or_create_one_locked."
        end

        # Currently this is optimized with the assumption that the desired document exists and is unlocked.  If
        # the most probable use case is that the document does not exist, this will need to be modified to improve
        # performance.
        def find_or_create_one_locked(qualifier,
                               values_on_create,
                               caller=default_locking_agent,
                               collection:self.default_collection,
                               lock_wait_duration: default_lock_wait_duration,
                               lock_hold_duration: default_lock_hold_duration)
          find_one_locked( qualifier, caller, collection:collection, lock_wait_duration:lock_wait_duration, lock_hold_duration:lock_hold_duration ) ||
             create_one_locked( values_on_create, caller, collection:collection, lock_hold_duration:lock_hold_duration )
        end

        def find_one_locked(qualifier,
                     caller=default_locking_agent,
                     collection: self.default_collection,
                     lock_wait_duration: default_lock_wait_duration,
                     lock_hold_duration: default_lock_hold_duration,
                     oldest: false,
                     **other_args
        )

          options = { return_document: :after }
          options.merge!( { sort: { updated_timestamp: 1}  }) if oldest
          image = collection.find_one_and_update(
              unlocked_qualifier(qualifier, caller),
              { '$set' => locked_values({}, caller, lock_hold_duration: lock_hold_duration)},
              options )

          unless image
            if lock_wait_duration > 0 && collection.find( qualifier ).limit(1).first
              interruptible_wait_loop_with_timeout( caller, lock_wait_duration: lock_wait_duration ) {
                image = collection.find_one_and_update(
                    unlocked_qualifier(qualifier, caller),
                    { '$set' => locked_values({}, caller, lock_hold_duration: lock_hold_duration)},
                    options )
                break if image
              }
            end
          end
          image ? new( image, collection: collection, **other_args ) : nil
        rescue => e
          raise Armagh::Connection.convert_mongo_exception( e)
        end

        def find_one_by_internal_id_locked(internal_id, caller=default_locking_agent, collection: self.default_collection, lock_wait_duration: default_lock_wait_duration, lock_hold_duration: default_lock_hold_duration  )
          find_one_locked( { '_id' => internal_id }, caller, collection: collection, lock_wait_duration: lock_wait_duration, lock_hold_duration: lock_hold_duration )
        end
        alias_method :get_locked, :find_one_by_internal_id_locked

        def find_one_by_document_id_locked(document_id, caller=default_locking_agent, collection: self.default_collection )
          find_one_locked( { 'document_id' => document_id}, caller, collection: collection)
        end


      end

      # Saves the current document to the @collection.
      #
      # If the document was last saved under a different internal_id or collection, that last-saved version is deleted.
      def save( unlock=true, caller=self.class.default_locking_agent, with_internal_id: nil, in_collection: nil, replacing: false, lock_hold_duration: self.class.default_lock_hold_duration )

        raise ReadOnlyError, "#{natural_key} is read-only and cannot be saved" if @read_only
        begin
          original_internal_id = @image[ '_id' ]
          target_internal_id = with_internal_id || original_internal_id

          original_collection = @_collection
          target_collection = in_collection || original_collection
          changing_collections = ( target_collection != original_collection )

          original_timestamps = set_timestamps
          save_content = ContentCleanup.clean_image(@image)
          presave_lock = @image['_locked']
          @image = unlock ? save_content.merge({ '_locked' => false }) : self.class.locked_values( save_content, caller, lock_hold_duration:lock_hold_duration )

          if target_internal_id && (replacing || !changing_collections)
            @image['_id'] = target_internal_id
            result = target_collection.replace_one( self.class.unlocked_or_my_qualifier({ '_id' => target_internal_id }, caller), @image )
            raise( LockExpiredError, "Document lock expired before save was attempted; save aborted." ) unless result.modified_count == 1
            @_collection = target_collection
          else
            @image['_id'] = target_collection.insert_one( @image ).inserted_ids.first
            @_collection = target_collection
          end
          if changing_collections && original_internal_id
            result = original_collection.delete_one(self.class.unlocked_or_my_qualifier({'_id' => original_internal_id }, caller))
            raise Connection::ConnectionError, "Unable to delete #{ natural_key } from #{@_collection_last_saved.name}" unless result.deleted_count == 1
          end
        rescue => e
          set_timestamps( original_timestamps ) if original_timestamps
          @image[ '_locked' ] = presave_lock
          raise Connection.convert_mongo_exception( e, natural_key: natural_key )
        end
        self
      end

      def delete( caller=self.class.default_locking_agent )
        raise ReadOnlyError, "#{natural_key} is read-only and cannot be deleted" if @read_only

        begin
          deleting_from_collection = @_collection_last_saved || @_collection
          result = deleting_from_collection.delete_one( self.class.unlocked_or_my_qualifier({ '_id' => internal_id }, caller) )
          raise Connection::ConnectionError, "Unable to delete #{ natural_key } from #{deleting_from_collection.name}" unless result.deleted_count == 1
          @_collection_last_saved = nil
          @image[ '_id' ] = nil
          nil
        rescue => e
          raise Connection.convert_mongo_exception(e)
        end

      end

      def locked_by
        @image['_locked']['by'] if locked_by_anyone?
      end

      def locked_by_anyone?
        @image['_locked'].is_a?(Hash) ? @image['_locked']&.[]('until') > Time.now.utc : false
      end

      def locked_by_me_until( me )
        @image['_locked']['until'] if locked_by == me.signature
      end

      def read_only?
        @read_only
      end

      def self.included( base )
       base.extend ClassMethods
      end
    end
  end
end
