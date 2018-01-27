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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/document/document'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class FakeAgent
  attr_accessor :signature
  def initialize(sig)
    @signature = sig
  end
  def running?() true; end
end

class TestDocumentIntegration < Test::Unit::TestCase

  def setup
    MongoSupport.instance.clean_database
    Armagh::Connection.clear_indexed_doc_collections
    Armagh::Connection.index_doc_collection( Armagh::Connection.documents )

    @agent = FakeAgent.new('iami')

  end

  def test_document_get_for_processing_order
    4.times do |count|
      Armagh::Document.create_one_unlocked(
          {
             type: 'TestDocument',
             content: {},
             metadata: {},
             pending_actions: ['action'],
             state: Armagh::Documents::DocState::READY,
             document_id: "doc_#{count}",
             collection_task_ids: []
          }
      )
    end

    doc = Armagh::Document.create_one_locked(
        {
            type: 'PublishedTestDocument',
            content: {},
            metadata: {},
            pending_actions: ['action'],
            state: Armagh::Documents::DocState::READY,
            document_id:'published_document',
            collection_task_ids: []
        },
        @agent
    )
    sleep 1
    doc.state = Armagh::Documents::DocState::PUBLISHED
    doc.save( true, @agent )

    # Make doc_3 more recently updated
    Armagh::Document.with_new_or_existing_locked_document('doc_3', 'TestDocument', Armagh::Documents::DocState::READY, @agent ) do |doc|
      doc.content['modified'] = true
    end

    # Make doc_1 most recently updated
    Armagh::Document.with_new_or_existing_locked_document('doc_1', 'TestDocument', Armagh::Documents::DocState::READY, @agent ) do |doc|
      doc.content['modified'] = true
    end

    other_agents = []
    5.times { |i|  other_agents << FakeAgent.new( "iam#{i}")}

    [
      [ 'doc_0', other_agents[0]],
      [ 'doc_2', other_agents[1]],
      [ 'doc_3', other_agents[2]],
      [ 'doc_1', other_agents[3]],
      [ 'published_document', other_agents[4]]
    ].each do | doc_id, held_by_agent |
      Thread.new do
         Armagh::Document.get_one_for_processing_locked( held_by_agent ) do |doc|
           assert_equal doc_id, doc.document_id
           sleep 6
         end
      end
      sleep 1
    end
  end

  def test_document_too_large
    content = {'field' => 'a'*100_000_000}
    assert_raise(Armagh::Connection::DocumentSizeError) do
      Armagh::Document.create_one_locked(
          {
              'type' => 'TestDocument',
              'content' => content,
              'metadata' => {},
              'pending_actions' => ['action'],
              'state' => Armagh::Documents::DocState::READY,
              'document_id' => 'test_doc'
          },
          @agent
      )
    end
  end

  def test_create_duplicate
    Armagh::Document.create_one_locked({
       'type' => 'TestDocument',
       'content' => {},
       'metadata' => {},
       'pending_actions' => ['action'],
       'state' => Armagh::Documents::DocState::READY,
       'document_id' => 'test_doc',
       'collection_task_ids' => []
      },
      @agent
    )

    assert_raise(Armagh::Connection::DocumentUniquenessError) do
      Armagh::Document.create_one_locked({
        'type' => 'TestDocument',
        'content' => {},
        'metadata' => {},
        'pending_actions' => ['action'],
        'state' => Armagh::Documents::DocState::READY,
        'document_id' => 'test_doc',
        'collection_task_ids' => []},
      @agent )
    end
  end

  def test_document_force_unlock

    id = 'doc_test'
    Armagh::Document.create_one_locked({
        'type' => 'TestDocument',
        'content' => {},
        'metadata' => {},
        'pending_actions' => ['action'],
        'state' => Armagh::Documents::DocState::READY,
        'document_id' => id,
        'collection_task_ids' => []
      },
      @agent,
      lock_hold_duration: 1
    )
    sleep 2

    Armagh::Document.get_one_for_processing_locked(@agent) {}

    doc = Armagh::Document.find_one_read_only({ 'document_id' => id }, collection: Armagh::Connection.documents )
    assert_true doc.locked_by_anyone?
    assert_equal(@agent.signature, doc.locked_by)

    Armagh::Document.force_unlock_all_in_collection_held_by(@agent)

    doc = Armagh::Document.find_one_read_only({ 'document_id' => id }, collection: Armagh::Connection.documents )
    assert_false doc.locked_by_anyone?
    assert_nil doc.locked_by

    assert_nothing_raised {Armagh::Document.force_unlock_all_in_collection_held_by(@agent)}
  end

  def test_count_failed_and_in_process_documents_by_doctype


    n = 0
    [
      [ 'doc_type1', Armagh::Documents::DocState::READY,     nil, false, 4 ],
      [ 'doc_type2', Armagh::Documents::DocState::READY,     nil, false, 5 ],
      [ 'doc_type3', Armagh::Documents::DocState::READY,     nil, false, 6 ],
      [ 'pub_type1', Armagh::Documents::DocState::PUBLISHED, nil, false, 5 ],
      [ 'pub_type1', Armagh::Documents::DocState::PUBLISHED, ['act'], false, 3 ],
      [ 'pub_type1', Armagh::Documents::DocState::PUBLISHED, nil, true, 2 ],
      [ 'doc_type2', Armagh::Documents::DocState::READY, nil, true, 1 ]
    ].each do |dtype, dstate, pending_actions, failed, number|

      number.times do |i|
        doc = Armagh::Document.create_one_locked({
            'type' => dtype,
            'content' => {},
            'metadata' => {},
            'pending_actions' => pending_actions,
            'state' => Armagh::Documents::DocState::READY,
            'document_id' => "test_#{n}",
          },
          @agent
        )
        n += 1
        if failed
          doc.add_error_to_dev_errors( 'bad_action', 'error_msg_here')
          doc.save(true,@agent)
        end

        if dstate == Armagh::Documents::DocState::PUBLISHED
          doc.state = dstate
          doc.save(true,@agent)
        end
      end
    end

    sleep 1
    Armagh::Document.clear_document_counts
    expected_counts = [
        { 'category' => 'in process', 'docspec_string' => 'doc_type1:ready',     'count' => 4, 'published_collection' => nil },
        { 'category' => 'in process', 'docspec_string' => 'doc_type2:ready',     'count' => 5, 'published_collection' => nil },
        { 'category' => 'in process', 'docspec_string' => 'doc_type3:ready',     'count' => 6, 'published_collection' => nil },
        { 'category' => 'failed',     'docspec_string' => 'doc_type2:ready',     'count' => 1, 'published_collection' => nil },
        { 'category' => 'in process', 'docspec_string' => 'pub_type1:published', 'count' => 3, 'published_collection' => 'pub_type1' }
    ]
    counts = Armagh::Document.count_failed_and_in_process_documents_by_doctype
    assert_equal expected_counts.sort_by{ |c| c['count']}, counts.sort_by{ |c| c['count']}
  end
end
