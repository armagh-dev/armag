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
require_relative '../../lib/connection'
require_relative '../../lib/agent/agent'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'
require 'connection'
require 'armagh/actions'

class TestEditCallback < Test::Unit::TestCase

  class TestParser < Armagh::ParseAction
    attr_accessor :doc_id
    attr_accessor :doc_was_new
    attr_reader :doc_class

    def parse(_trigger)
      edit(@doc_id, 'test_document') do |doc|
        @doc_class = doc.class
        doc.meta['field'] = true
        doc.draft_content = 'DRAFT CONTENT'
        @doc_was_new = doc.new_document?
      end
    end
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

    @output_type = 'OutputDocument'
    @output_state = Armagh::DocState::WORKING
    output_docspecs = {'test_document' => Armagh::DocSpec.new(@output_type, @output_state)}
    @parser = TestParser.new('parser', Armagh::Agent.new, @logger, {}, output_docspecs)
  end

  def test_edit_new
    @parser.doc_id = 'non_existing_doc_id'
    assert_nil Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    action_doc = Armagh::ActionDocument.new('triggering_id', {}, {}, {}, Armagh::DocSpec.new('TriggerDocument', Armagh::DocState::READY))
    @parser.parse(action_doc)

    assert_equal(Armagh::ActionDocument, @parser.doc_class)
    assert_true(@parser.doc_was_new)

    doc = Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@parser.doc_id, doc.id)
    assert_equal('DRAFT CONTENT', doc.draft_content)
    assert_equal({'field' => true}, doc.meta)
    assert_false doc.locked?
  end

  def test_edit_existing
    doc_id = 'existing_doc_id'
    assert_nil Armagh::Document.find(doc_id, @output_type, @output_state)
    Armagh::Document.create(@output_type, {'draft_content' => 456}, {'published_content' => 123}, {'meta' => 'bananas'}, [], @output_state, doc_id)
    doc = Armagh::Document.find(doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_false doc.locked?

    @parser.doc_id = doc_id
    action_doc = Armagh::ActionDocument.new('triggering_id', {}, {}, {}, Armagh::DocSpec.new('TriggerDocument', Armagh::DocState::READY))
    @parser.parse(action_doc)

    doc = Armagh::Document.find(@parser.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@parser.doc_id, doc.id)
    assert_equal('DRAFT CONTENT', doc.draft_content)
    assert_equal({'field' => true, 'meta' => 'bananas'}, doc.meta)
    assert_false doc.locked?
  end
end
