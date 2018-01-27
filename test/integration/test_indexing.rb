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
require_relative '../../lib/armagh/agent/agent'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestIndexing < Test::Unit::TestCase

  def setup
    MongoSupport.instance.clean_database
    Armagh::Connection.clear_indexed_doc_collections
    Armagh::Connection.setup_indexes
    @agent = Object.new
    def @agent.signature() 'iami'; end
    def @agent.running?() true; end
  end

  def get_index_stats(collection, index_name)
    collection.aggregate([{'$indexStats' => {}}]).entries.each do |index|
      return index if index['name'] == index_name
    end
  end

  def create_documents(state)
    4_000.times { |i| create_document("id_#{i}", 'TestDocument', state) }
    Armagh::Document.force_unlock_all_in_collection_held_by @agent
    Armagh::Document.force_unlock_all_in_collection_held_by @agent, collection: Armagh::Connection.documents('TestDocument')
  end

  def create_document(id, type = 'TestDocument', state = Armagh::Documents::DocState::READY)
    doc = Armagh::Document.create_one_unlocked(
        {
            type: type,
            content: {},
            metadata: {},
            pending_actions: ['action'],
            state: Armagh::Documents::DocState::READY,
            document_id: id
        }
    )
    unless state == Armagh::Documents::DocState::READY
      doc.state = state
      doc.save( true, @agent )
    end

  end

  def test_config_idx

    Armagh::Agent.create_configuration(Armagh::Connection.config, 'default', {})

    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Agent.find_configuration(Armagh::Connection.config, 'default')

    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    new_ops = index_stats['accesses']['ops']
    assert_equal(initial_ops + 1, new_ops)

    Armagh::Agent.find_configuration(Armagh::Connection.config, 'default')

    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    new_ops = index_stats['accesses']['ops']
    assert_equal(initial_ops + 2, new_ops)
  end

  def test_get_for_processing_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'pending_unlocked')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.get_one_for_processing_locked(@agent) do |d|
      sleep 1
    end

    index_stats = get_index_stats(Armagh::Connection.documents, 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_get_for_processing_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.get_one_for_processing_locked(@agent) do |d|
      sleep 1
    end

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_one_by_document_id_type_state_read_only('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_one_by_document_id_type_state_read_only('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_exists
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.exists?('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_exists_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.exists?('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_one_locked_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_one_by_document_id_type_state_locked('id_0', 'TestDocument', Armagh::Documents::DocState::READY, @agent)

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_one_locked_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_one_by_document_id_type_state_locked('id_0', 'TestDocument', Armagh::Documents::DocState::PUBLISHED, @agent)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_unpubished_doc_uniqueness
    assert_nothing_raised {
      create_document(nil, 'Type')
      create_document(nil, 'Type')
    }

    create_document('id_123', 'Type')
    assert_raise(Armagh::Connection::DocumentUniquenessError) { create_document('id_123', 'Type') }

    assert_nothing_raised {
      create_document('id_123', 'Type1')
      create_document('id_123', 'Type2')
    }
  end

  def test_published_doc_uniqueness
    create_document('id_123', 'Type', Armagh::Documents::DocState::PUBLISHED)
    assert_raise(Armagh::Connection::DocumentUniquenessError) {
      create_document('id_123', 'Type', Armagh::Documents::DocState::PUBLISHED)
    }

    assert_nothing_raised {
      create_document('id_123', 'Type1', Armagh::Documents::DocState::PUBLISHED)
      create_document('id_123', 'Type2', Armagh::Documents::DocState::PUBLISHED)
    }
  end
end
