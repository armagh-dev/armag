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

require_relative '../../lib/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/connection'
require_relative '../../lib/document/document'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestDocumentIntegration < Test::Unit::TestCase

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end

  def setup
    MongoSupport.instance.clean_database
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
    Armagh::Document.modify_or_create('doc_3', 'TestDocument', Armagh::Documents::DocState::READY, true) do |doc|
      doc.content['modified'] = true
    end

    # Make doc_1 most recently updated
    Armagh::Document.modify_or_create('doc_1', 'TestDocument', Armagh::Documents::DocState::READY, true) do |doc|
      doc.content['modified'] = true
    end

    # Expected order (based on last update and published first) - published_document, doc_0, doc_2, doc_3, doc_1
    assert_equal('doc_0', Armagh::Document.get_for_processing.document_id)
    assert_equal('doc_2', Armagh::Document.get_for_processing.document_id)
    assert_equal('doc_3', Armagh::Document.get_for_processing.document_id)
    assert_equal('doc_1', Armagh::Document.get_for_processing.document_id)
    assert_equal('published_document', Armagh::Document.get_for_processing.document_id)
  end

  def test_document_too_large
    content = {'field' => 'a'*100_000_000}
    assert_raise(Armagh::Documents::Errors::DocumentSizeError) do
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

    assert_raise(Armagh::Documents::Errors::DocumentUniquenessError) do
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
end
