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

require_relative '../utils/exception_helper'
require_relative '../utils/processing_backoff'
require_relative 'base_document/document'
require_relative 'base_document/locking_crud'

require 'armagh/documents'
require 'armagh/support/encoding'

require 'bson'

module Armagh
  class Document < BaseDocument::Document
    include BaseDocument::LockingCRUD

    class DocumentMarkError < StandardError;
    end

    COUNT_QUERY_INTERVAL_IN_SECONDS = 2

    def self.default_collection
      Connection.documents
    end

    def self.armagh_version
      @armagh_version ||= {}
    end

    attr_accessor :published_id
    delegated_attr_accessor       :armagh_version
    delegated_attr_accessor       :title
    delegated_attr_accessor       :copyright
    delegated_attr_accessor       :published_timestamp, validates_with: :utcize_ts
    delegated_attr_accessor_array :collection_task_ids
    delegated_attr_accessor       :source
    delegated_attr_accessor       :document_timestamp,  validates_with: :utcize_ts
    delegated_attr_accessor       :display
    delegated_attr_accessor       :content
    delegated_attr_accessor       :metadata
    delegated_attr_accessor       :type
    delegated_attr_accessor_array :archive_files
    delegated_attr_accessor       :raw,                 validates_with: :validate_raw,  after_return: :get_raw_data
    delegated_attr_accessor       :state,               validates_with: :validate_state
    delegated_attr_accessor_array :pending_actions,     after_change: :update_pending_work
    delegated_attr_accessor       :error
    delegated_attr_accessor_errors :dev_errors,         after_change: :update_error_and_pending_work
    delegated_attr_accessor_errors :ops_errors,         after_change: :update_error_and_pending_work
    delegated_attr_accessor       :pending_work
    delegated_attr_accessor       :version

    alias_method :add_dev_error, :add_error_to_dev_errors
    alias_method :add_ops_error, :add_error_to_ops_errors

    def validate_raw(raw)
      if raw.is_a?(String)
        BSON::Binary.new(raw)
      elsif raw.nil?
        nil
      elsif raw.is_a?(BSON::Binary)
        raw
      else
        raise TypeError, 'Value for raw expected to be a string.'
      end
    end

    def get_raw_data(raw)
      raw&.data
    end

    def validate_state(state)
      if Documents::DocState.valid_state?(state)
        state
      else
        raise Documents::Errors::DocStateError.new "Tried to set state to an unknown state: '#{state}'."
      end
    end

    def self.from_action_document(action_doc, pending_actions = [])
      doc = Document.new
      doc.update_from_draft_action_document(action_doc)
      doc.add_items_to_pending_actions pending_actions
      doc
    end

    def self.with_new_or_existing_locked_document( document_id, type, state, caller=self.class.default_locking_agent, **other)
      super( { 'document_id' => document_id, 'type' => type },
             {'document_id' => document_id, 'type' => type, 'state' => state},
             caller,
             collection: self.collection( type, state ),
             **other
      )
    end

    def self.count_failed_and_in_process_documents_by_doctype

      @dont_count_again_until ||= Time.now - 1

      if @dont_count_again_until < Time.now

        @failed_and_in_process_documents_by_doctype = []

        pub_types = Connection.all_published_collections

        queries = [
            { category: 'in process', doc_colls: [ Connection.documents ], filter: nil },
            { category: 'failed',     doc_colls: [ Connection.failures ],  filter: nil },
            { category: 'in process', doc_colls: pub_types,                filter: { 'pending_work' => true }},
            { category: 'failed',     doc_colls: pub_types,                filter: { 'error' => true }}
        ]

        queries.each do |query|

          query[:doc_colls].each do |doc_coll|

            match_clause = query[:filter] ? { '$match' => query[:filter] } : nil
            pipeline = [
                match_clause,
                {'$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}
            ].compact
            counts_this_query = doc_coll.aggregate( pipeline ).to_a
            counts_this_query.each do |count_detail|
              @failed_and_in_process_documents_by_doctype << {
                  'category'             => query[:category],
                  'published_collection' => doc_coll.name.split(".")[1],
                  'docspec_string'       => "#{count_detail['_id']['type']}:#{count_detail['_id']['state']}",
                  'count'                => count_detail[ 'count' ].to_i
              }
            end
          end
        end
        @dont_count_again_until = Time.now + COUNT_QUERY_INTERVAL_IN_SECONDS
      end
      @failed_and_in_process_documents_by_doctype
    end

    def self.clear_document_counts
      @dont_count_again_until = Time.now - 1
    end

    def self.find_many_by_ts_range_read_only(doc_type, begin_ts, end_ts, page_number, page_size)
      qualifier = {}
      ts_qualifier = {}
      ts_qualifier['$gte'] = begin_ts if begin_ts
      ts_qualifier['$lte'] = end_ts if end_ts
      qualifier['document_timestamp'] = ts_qualifier unless ts_qualifier.empty?

      paging = { page_number: page_number || 0, page_size: page_size || 20}

      find_many_read_only(qualifier,
                          collection: collection(doc_type, Documents::DocState::PUBLISHED),
                          sort_rule: { 'document_timestamp' => -1 },
                          paging: paging )
    end

    def self.find_one_by_document_id_type_state_locked(document_id, type, state, caller=default_locking_agent )
      find_one_by_document_id_locked( document_id, caller, collection: collection(type, state))
    end

    def self.find_one_by_document_id_type_state_read_only( document_id, type, state )
      find_one_by_document_id_read_only( document_id, collection: collection( type, state ))
    end

    def self.find_all_failures_read_only
      find_many_read_only( {}, collection: Connection.failures )
    end

    def self.get_one_for_processing_locked( caller=default_locking_agent, **other_args )
      Connection.all_document_collections.each do |collection|
        begin
          doc = find_one_locked( { 'pending_work' => true }, caller, collection: collection, oldest: true, lock_wait_duration: 0, **other_args )
          if doc
            yield doc
            doc.save( true, caller )
            return true
          end
        rescue Armagh::BaseDocument::LockTimeoutError => e
          # ignore and move on to next collect
        end
      end
      return false
    end

    def self.exists?(document_id, type, state)
      find_one_read_only({'document_id' => document_id, 'type' => type}, collection: collection(type, state)) != nil
    rescue => e
      raise Connection.convert_mongo_exception(e, natural_key: "#{self.name.split("::").last} #{document_id}" )
    end

    def self.collection(type = nil, state = nil)
      type_collection = (state == Documents::DocState::PUBLISHED) ? type : nil
      Connection.documents(type_collection)
    end

    def initialize(image = {}, **args)
      @pending_delete = false
      @pending_publish = false
      @pending_collection_history = false
      @abort = false
      super(image, args)
      self.metadata ||= {}
      self.source = Armagh::Documents::Source.new( **Hash[ self.source.collect{ |k,v| [ k.to_sym, v ]} ]) if self.source.is_a?(Hash)
      self.pending_actions ||= []
      clear_errors
    end

    def clear_errors
      clear_dev_errors
      clear_ops_errors
    end

    def errors
      dev_errors.merge(ops_errors) {|_key, left, right| left + right}
    end

    def pending_work?
      pending_work ? true : false
    end

    def save( unlock = true, caller = self.class.default_locking_agent )

      if !error && ((@abort && !published?) || @pending_delete)
        delete
      else

        self.armagh_version = self.class.armagh_version
        self.collection_task_ids.uniq!
        self.archive_files.uniq!

        save_to_collection = case
                            when (error && !published?)      then Connection.failures
                            when @pending_publish            then Connection.documents(type)
                            when @pending_collection_history then Connection.collection_history
                            when published?                  then Connection.documents(type)
                            else                                  Connection.documents
                          end

        save_options = {}
        save_options[ :in_collection ] = save_to_collection if @_collection != save_to_collection
        if @pending_publish && @published_id
          save_options[ :with_internal_id ] = @published_id
          save_options[ :replacing ] = true
        end

        source_object_memo = self.source
        @image = Support::Encoding.fix_encoding(@image, proposed_encoding: self.source&.encoding )
        self.source = self.source.to_hash if self.source.is_a?( Armagh::Documents::Source )
        super( unlock, caller, **save_options )
        self.source = source_object_memo
      end

      clear_marks
      @published_id = nil

      self
    rescue => e
      raise Connection.convert_mongo_exception(e, natural_key: natural_key)
    end

    def to_hash
      source_object_memo = self.source
      self.source = self.source.to_hash  if self.source.is_a?( Armagh::Documents::Source )
      hash_result = super
      self.source = source_object_memo
      hash_result
    end

    def ready?
      state == Documents::DocState::READY
    end

    def working?
      state == Documents::DocState::WORKING
    end

    def published?
      state == Documents::DocState::PUBLISHED
    end

    def get_published_copy_read_only
      self.class.find_one_by_document_id_type_state_read_only(document_id, type, Documents::DocState::PUBLISHED)
    end

    def self.get_published_copy_read_only( document_id, type )
      find_one_by_document_id_type_state_read_only(document_id, type, Documents::DocState::PUBLISHED)
    end

    def to_action_document
      Documents::ActionDocument.new(
          document_id: document_id.deep_copy,
          title: title.deep_copy,
          copyright: copyright.deep_copy,
          content: (content.deep_copy || {}),
          raw: raw.deep_copy,
          metadata: metadata.deep_copy,
          docspec: Documents::DocSpec.new(type, state),
          source: source,
          document_timestamp: document_timestamp,
          display: display.deep_copy,
          version: version,
          new: (internal_id.nil? || (updated_timestamp == created_timestamp) )
      )
    end

    def to_published_document
      Documents::PublishedDocument.new(
          document_id: document_id.deep_copy,
          title: title.deep_copy,
          copyright: copyright.deep_copy,
          content: content.deep_copy,
          raw:raw.deep_copy,
          metadata: metadata.deep_copy,
          docspec: Documents::DocSpec.new(type, state),
          source: source,
          document_timestamp: document_timestamp,
          display: display.deep_copy,
          version: version,
      )
    end

    def update_from_draft_action_document(action_doc)
      self.document_id = action_doc.document_id
      self.content = action_doc.content
      self.raw = action_doc.raw
      self.metadata = action_doc.metadata
      self.source = action_doc.source
      self.title = action_doc.title
      self.copyright = action_doc.copyright
      self.document_timestamp = action_doc.document_timestamp
      self.display = action_doc.display
      self.version = action_doc.version
      docspec = action_doc.docspec
      self.type = docspec.type
      self.state = docspec.state
      self
    end

    def mark_delete
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or publish.' if @pending_collection_history || @pending_publish
      @pending_delete = true
    end

    def mark_publish
      raise DocumentMarkError, 'Document cannot be marked as archive.  It is already marked for archive or delete.' if @pending_collection_history || @pending_delete
      @pending_publish = true
    end

    def mark_collection_history
      raise DocumentMarkError, 'Document cannot be marked to save collection history.  It is already marked for delete or publish.' if @pending_delete || @pending_publish
      @pending_collection_history = true
    end

    def mark_abort
      clear_marks
      @abort = true
    end

    def clear_marks
      @pending_delete = false
      @pending_publish = false
      @pending_collection_history = false
      @abort = false
    end

    private def update_pending_work( _pending_actions=nil)
      if pending_actions.any? && !error
        self.pending_work = true
      else
        delete_pending_work
      end
      pending_actions
    end

    private def update_error_and_pending_work( original_error_info )
      if dev_errors.any? || ops_errors.any?
        self.error = true
      else
        delete_error
      end
      update_pending_work
      original_error_info
    end
  end
end
