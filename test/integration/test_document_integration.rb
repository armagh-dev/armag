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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require_relative '../../lib/document/document'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestDocumentIntegration < Test::Unit::TestCase

  def setup
    MongoSupport.instance.clean_database
    Armagh::Connection.clear_indexed_doc_collections
    Armagh::Connection.index_doc_collection( Armagh::Connection.documents )
  end

  def test_document_get_for_processing_order
    4.times do |count|
      Armagh::Document.create(type: 'TestDocument',
                              content: {},
                              metadata: {},
                              pending_actions: ['action'],
                              state: Armagh::Documents::DocState::READY,
                              document_id: "doc_#{count}",
                              collection_task_ids: [],
                              document_timestamp: nil)
      sleep 1
    end

    Armagh::Document.create(type: 'PublishedTestDocument',
                            content: {},
                            metadata: {},
                            pending_actions: ['action'],
                            state: Armagh::Documents::DocState::PUBLISHED,
                            document_id:'published_document',
                            collection_task_ids: [],
                            document_timestamp: nil)

    # Make doc_3 more recently updated
    Armagh::Document.modify_or_create('doc_3', 'TestDocument', Armagh::Documents::DocState::READY, true, 'test-agent') do |doc|
      doc.content['modified'] = true
    end

    # Make doc_1 most recently updated
    Armagh::Document.modify_or_create('doc_1', 'TestDocument', Armagh::Documents::DocState::READY, true, 'test-agent') do |doc|
      doc.content['modified'] = true
    end

    # Expected order (based on last update and published first) - published_document, doc_0, doc_2, doc_3, doc_1
    d = Armagh::Document.get_for_processing('test-agent1')
    assert_equal('doc_0', d.document_id)
    assert_equal('test-agent1', d.locked_by)
    assert_true(d.locked?)

    assert_equal('doc_2', Armagh::Document.get_for_processing('test-agent2').document_id)
    assert_equal('doc_3', Armagh::Document.get_for_processing('test-agent3').document_id)
    assert_equal('doc_1', Armagh::Document.get_for_processing('test-agent4').document_id)
    assert_equal('published_document', Armagh::Document.get_for_processing('test-agent5').document_id)
  end

  def test_document_too_large
    content = {'field' => 'a'*100_000_000}
    assert_raise(Armagh::Connection::DocumentSizeError) do
      Armagh::Document.create(type: 'TestDocument',
                              content: content,
                              metadata: {},
                              pending_actions: ['action'],
                              state: Armagh::Documents::DocState::READY,
                              document_id: 'test_doc',
                              collection_task_ids: [],
                              document_timestamp: nil)
    end
  end

  def test_create_duplicate
    Armagh::Document.create(type: 'TestDocument',
                            content: {},
                            metadata: {},
                            pending_actions: ['action'],
                            state: Armagh::Documents::DocState::READY,
                            document_id: 'test_doc',
                            new: true,
                            collection_task_ids: [],
                            document_timestamp: nil)

    assert_raise(Armagh::Connection::DocumentUniquenessError) do
      Armagh::Document.create(type: 'TestDocument',
                              content: {},
                              metadata: {},
                              pending_actions: ['action'],
                              state: Armagh::Documents::DocState::READY,
                              document_id: 'test_doc',
                              new: true,
                              collection_task_ids: [],
                              document_timestamp: nil)
    end
  end

  def test_document_force_unlock
    agent_id = 'test-agent-id'
    id = 'doc_test'
    Armagh::Document.create(type: 'TestDocument',
                            content: {},
                            metadata: {},
                            pending_actions: ['action'],
                            state: Armagh::Documents::DocState::READY,
                            document_id: id,
                            collection_task_ids: [],
                            document_timestamp: nil)
    sleep 1

    doc = Armagh::Document.find(id, 'TestDocument', Armagh::Documents::DocState::READY)
    assert_false doc.locked?
    assert_nil doc.locked_by

    Armagh::Document.get_for_processing(agent_id)

    doc = Armagh::Document.find(id, 'TestDocument', Armagh::Documents::DocState::READY)
    assert_true doc.locked?
    assert_equal(agent_id, doc.locked_by)

    Armagh::Document.force_unlock(agent_id)

    doc = Armagh::Document.find(id, 'TestDocument', Armagh::Documents::DocState::READY)
    assert_false doc.locked?
    assert_nil doc.locked_by

    assert_nothing_raised {Armagh::Document.force_unlock('not an existing id')}
  end

  def test_count_incomplete_all
    n = 0
    [
      [ 'doc_type1', Armagh::Documents::DocState::READY,     nil, false, 4 ],
      [ 'doc_type2', Armagh::Documents::DocState::READY,     nil, false, 5 ],
      [ 'doc_type3', Armagh::Documents::DocState::READY,     nil, false, 6 ],
      [ 'pub_type1', Armagh::Documents::DocState::PUBLISHED, nil, false, 5 ],
      [ 'pub_type1', Armagh::Documents::DocState::PUBLISHED, ['act'], false, 3 ],
      [ 'doc_type2', Armagh::Documents::DocState::READY, nil, true, 1 ]
    ].each do |dtype, dstate, pending_actions, failed, number|

      number.times do |i|
        doc = Armagh::Document.create(
          type: dtype,
          content: {},
          metadata: {},
          pending_actions: pending_actions,
          state: dstate,
          document_id: "test_#{n}",
          new: true,
          collection_task_ids: [],
          document_timestamp: nil)
        n += 1
        if failed
          doc.add_dev_error( 'bad_action', 'error_msg_here')
          doc.save
        end
      end
    end

    counts = Armagh::Document.count_incomplete_by_doctype
    expected_counts = {
        'documents' => { 'doc_type1:ready' => 4, 'doc_type2:ready' => 5, 'doc_type3:ready' => 6 },
        'documents.pub_type1' => { 'pub_type1:published' => 3 },
        'failures' => { 'doc_type2:ready' => 1}
    }
    assert_equal expected_counts, counts
  end
end
