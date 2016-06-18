# Copyright 2016 Noragh Analytics, Inc.
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
require_relative '../helpers/mongo_support'

require_relative '../../lib/configuration/launcher_config_manager'
require_relative '../../lib/configuration/agent_config_manager'
require_relative '../../lib/connection'
require_relative '../../lib/document/document'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestIndexing < Test::Unit::TestCase

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo
    MongoSupport.instance.clean_database
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

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
    4_000.times do |i|
      Armagh::Document.create(type: 'TestDocument', draft_content: {}, published_content: {},
                              draft_metadata: {}, published_metadata: {}, pending_actions: ['action'],
                              state: state, id: "id_#{i}")
    end
  end

  def test_config_idx
    MongoSupport.instance.set_config('launcher', {'launcher_details' => 'launcher config details'})
    MongoSupport.instance.set_config('agent', {'agent_details' => 'agent config details'})

    logger = stub(:ops_warn)
    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    initial_ops = index_stats['accesses']['ops']

    launcher_manager = Armagh::Configuration::LauncherConfigManager.new(logger)
    agent_manager = Armagh::Configuration::AgentConfigManager.new(logger)

    launcher_manager.get_config

    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    new_ops = index_stats['accesses']['ops']
    assert_equal(initial_ops + 1, new_ops)

    agent_manager.get_config

    index_stats = get_index_stats(Armagh::Connection.config, 'types')
    new_ops = index_stats['accesses']['ops']
    assert_equal(initial_ops + 2, new_ops)
  end

  def test_get_for_processing_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, 'pending_unlocked')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.get_for_processing

    index_stats = get_index_stats(Armagh::Connection.documents, 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_get_for_processing_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.get_for_processing

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), 'pending_unlocked')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_exists
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.exists?('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_exists_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.exists?('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_or_create_and_lock_idx
    create_documents Armagh::Documents::DocState::READY

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_or_create_and_lock('id', 'TestDocument', Armagh::Documents::DocState::READY)

    index_stats = get_index_stats(Armagh::Connection.documents, '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)
  end

  def test_find_or_create_and_lock_idx_published
    create_documents Armagh::Documents::DocState::PUBLISHED

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    initial_ops = index_stats['accesses']['ops']

    Armagh::Document.find_or_create_and_lock('id', 'TestDocument', Armagh::Documents::DocState::PUBLISHED)

    index_stats = get_index_stats(Armagh::Connection.documents('TestDocument'), '_id_')
    new_ops = index_stats['accesses']['ops']

    assert_equal(initial_ops + 1, new_ops)

  end
  
end
