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
require_relative 'delegated_attributes'
require_relative 'non_locking_crud'
require_relative 'content_cleanup'

module Armagh
  module BaseDocument

    class NoChangesAllowedError < StandardError; end
    class DefaultCollectionUndefinedError < StandardError; end

    class Document
      include DelegatedAttributes
      include NonLockingCRUD

      delegated_attr_accessor 'internal_id', '_id', validates_with: :no_changes_allowed
      delegated_attr_accessor 'document_id'
      delegated_attr_accessor 'updated_timestamp', validates_with: :utcize_ts
      delegated_attr_accessor 'created_timestamp', validates_with: :utcize_ts

      def no_changes_allowed( new_id )
        raise NoChangesAllowedError, "only the database can set internal_id"
      end

      def utcize_ts( ts )
        ts&.utc
      end

      def self.default_collection
        raise DefaultCollectionUndefinedError, 'class does not define a default_collection'
      end

      class << self
        protected :new
      end

      def initialize(image = {}, collection: nil, logger: nil, read_only: false)
        reset_image(image)
        @_collection = collection || self.class.default_collection
        @logger = logger
        @read_only = read_only
      end

      def reset_image( image = {} )
        @image = {}
        clean_image = ContentCleanup.restore_image( image )
        clean_image.each do |k,v|
          ( /^\_/=~ k ) ? @image[k] = v : send( "#{k}=",v)            # make sure validators are run
        end
      end

      def natural_key
        "#{self.class.name.split('::').last} #{ document_id }"
      end

      def set_timestamps( timestamps_buffer=nil )
        if timestamps_buffer
          self.updated_timestamp = timestamps_buffer[ :updated ]
          self.created_timestamp = timestamps_buffer[ :created ]
          return nil
        else
          timestamps_buffer = { updated: self.updated_timestamp, created: self.created_timestamp }
          now = Time.now
          self.updated_timestamp = now
          self.created_timestamp ||= now
          timestamps_buffer
        end
      end

      def new_document?
        self.updated_timestamp == self.created_timestamp
      end

      def to_s
        to_hash.to_s
      end

      def to_hash
        im = @image.deep_copy
        the_id = im['_id'].is_a?( BSON::ObjectId ) ? im['_id'].to_s : im['_id']
        im[ 'internal_id' ] = the_id
        im.delete '_id'
        im
      end

      def to_json(options = {})
        to_hash.to_json(options)
      end
    end
  end
end