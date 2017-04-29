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
require_relative '../../lib/agent/agent'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestIndexing < Test::Unit::TestCase

  def setup
    MongoSupport.instance.clean_database
    Armagh::Connection.clear_indexed_doc_collections
    Armagh::Connection.setup_indexes
  end

  def get_index_stats(collection, index_name)
    collection.aggregate([{'$indexStats' => {}}]).entries.each do |index|
      return index if index['name'] == index_name
    end
  end

  def create_documents(state)
    4_000.times { |i| create_document("id_#{i}", 'TestDocument', state) }
  end

  def create_document(id, type = 'TestDocument', state = Armagh::Documents::DocState::READY)
    Armagh::Document.create(type: type,
                            content: {},
                            metadata: {},
                            pending_actions: ['action'],
                            state: state,
                            document_id: id,
                            collection_task_ids: [],
                            document_timestamp: nil)
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

    Armagh::Document.get_for_processing('test_agent')

    index_stats = get_index_stats(Armagh::Connection.documents, 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_get_for_processing_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.get_for_processing('test_agent')

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

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

  def test_find_or_create_and_lock_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_or_create_and_lock('id', 'TestDocument', Armagh::Documents::DocState::READY, 'test-agent')

    index_stats = get_index_stats(Armagh::Connection.documents, 'document_ids')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_or_create_and_lock_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'published_document_ids')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_or_create_and_lock('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED, 'test-agent')

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
