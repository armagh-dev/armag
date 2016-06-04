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

require_relative '../../lib/connection'
require_relative '../../lib/agent/agent'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'
require 'connection'
require 'armagh/actions'

class TestEditCallback < Test::Unit::TestCase

  class TestParser < Armagh::Actions::Parse
    attr_accessor :doc_id
    attr_accessor :doc_was_new
    attr_reader :doc_class

    def parse(_trigger)
      edit(@doc_id, 'test_document') do |doc|
        @doc_class = doc.class
        doc.draft_metadata['field'] = true
        doc.draft_content = 'DRAFT CONTENT'
        @doc_was_new = doc.new_document?
      end
    end
  end

  class TestDocument
    attr_accessor :id
  end

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
    MongoSupport.instance.start_mongo unless MongoSupport.instance.running?
    MongoSupport.instance.clean_database

    agent = Armagh::Agent.new
    doc = TestDocument.new
    doc.id = 'some other id'

    agent.instance_variable_set(:@current_doc, doc)

    @output_type = 'OutputDocument'
    @output_state = Armagh::Documents::DocState::WORKING
    output_docspecs = {'test_document' => Armagh::Documents::DocSpec.new(@output_type, @output_state)}
    @parser = TestParser.new('parser', agent, @logger, {}, output_docspecs)
  end

  def test_edit_new
    @parser.doc_id = 'non_existing_doc_id'
    assert_nil Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    action_doc = Armagh::Documents::ActionDocument.new(id: 'triggering_id', draft_content: {}, published_content: {},
                                            draft_metadata: {}, published_metadata: {},
                                            docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY))
    @parser.parse(action_doc)

    assert_equal(Armagh::Documents::ActionDocument, @parser.doc_class)
    assert_true(@parser.doc_was_new)

    doc = Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@parser.doc_id, doc.id)
    assert_equal('DRAFT CONTENT', doc.draft_content)
    assert_equal({'field' => true}, doc.draft_metadata)
    assert_false doc.locked?
  end

  def test_edit_existing
    doc_id = 'existing_doc_id'
    assert_nil Armagh::Document.find(doc_id, @output_type, @output_state)
    Armagh::Document.create(type: @output_type, draft_content:{'draft_content' => 456},
                            published_content: {'published_content' => 123}, draft_metadata: {'draft_meta' => 'bananas'},
                            published_metadata: {'published_meta' => 'apples'},
                            pending_actions: [], state: @output_state, id: doc_id)
    doc = Armagh::Document.find(doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_false doc.locked?

    @parser.doc_id = doc_id
    action_doc = Armagh::Documents::ActionDocument.new(id: 'triggering_id', draft_content: {}, published_content: {},
                                            draft_metadata: {}, published_metadata: {},
                                            docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY))
    @parser.parse(action_doc)

    doc = Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@parser.doc_id, doc.id)
    assert_equal('DRAFT CONTENT', doc.draft_content)
    assert_equal({'field' => true, 'draft_meta' => 'bananas'}, doc.draft_metadata)
    assert_false doc.locked?
  end
end
