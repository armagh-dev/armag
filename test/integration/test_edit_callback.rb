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

require_relative '../../lib/logging'
require_relative '../../lib/connection'
require_relative '../../lib/agent/agent'
require_relative '../../lib/action/workflow'

require 'test/unit'

require 'mongo'
require 'connection'
require 'armagh/actions'

module Armagh
  module StandardActions
    class TestSplitter < Actions::Split
      define_output_docspec 'test_document', 'desc'
      
      attr_accessor :doc_id
      attr_accessor :doc_was_new
      attr_reader :doc_class

      def split(_trigger)
        edit(@doc_id, 'test_document') do |doc|
          @doc_class = doc.class
          doc.metadata['field'] = true
          doc.content = {'DRAFT CONTENT' => true}
          @doc_was_new = doc.new_document?
        end
      end
    end
  end
end

class TestEditCallback < Test::Unit::TestCase

  class TestDocument
    attr_accessor :document_id
  end

  def self.startup
    puts 'Starting Mongo'
    Singleton.__init__(Armagh::Connection::MongoConnection)
    MongoSupport.instance.start_mongo

#    Armagh::Logging.init_log_env
  end

  def self.shutdown
    puts 'Stopping Mongo'
    MongoSupport.instance.stop_mongo
  end
  
  def setup
    MongoSupport.instance.start_mongo unless MongoSupport.instance.running?
    MongoSupport.instance.clean_database
    @logger = Armagh::Logging.set_logger('Test::Logger')

    @output_type = 'OutputDocument'
    @output_state = Armagh::Documents::DocState::WORKING

    config_store = []
    workflow = Armagh::Actions::Workflow.new( nil, config_store )
    workflow.create_action( 
      'Armagh::StandardActions::TestSplitter', 
      { 'action' => { 'name' => 'test_splitter' },
        'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( 'intype', 'ready' )},
        'output' => { 'test_document' => Armagh::Documents::DocSpec.new( @output_type, @output_state )}
      }
    ) 
    agent_config = Armagh::Agent.create_configuration( config_store, 'default', {} )
    agent = Armagh::Agent.new( agent_config, workflow )

    @splitter = workflow.instantiate_action( 'test_splitter', agent, @logger, nil )

    doc = TestDocument.new
    doc.document_id = 'some other id'

    agent.instance_variable_set(:@current_doc, doc)

   end

  def test_edit_new
    @splitter.doc_id = 'non_existing_doc_id'
    assert_nil Armagh::Document.find(@splitter.doc_id, @output_type, @output_state)
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'triggering_id',
                                                       content: {},
                                                       metadata: {},
                                                       docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY),
                                                       source: {})
    @splitter.split(action_doc)

    assert_equal(Armagh::Documents::ActionDocument, @splitter.doc_class)
    assert_true(@splitter.doc_was_new)

    doc = Armagh::Document.find(@splitter.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@splitter.doc_id, doc.document_id)
    assert_equal({'DRAFT CONTENT' => true}, doc.content)
    assert_equal({'field' => true}, doc.metadata)
    assert_false doc.locked?
  end

  def test_edit_existing
    doc_id = 'existing_doc_id'
    assert_nil Armagh::Document.find(doc_id, @output_type, @output_state)
    Armagh::Document.create(type: @output_type,
                            content:{'content' => 123},
                            metadata: {'draft_meta' => 'bananas'},
                            pending_actions: [],
                            state: @output_state,
                            document_id: doc_id,
                            collection_task_ids: [],
                            document_timestamp: nil)
    doc = Armagh::Document.find(doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_false doc.locked?

    @splitter.doc_id = doc_id
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'triggering_id',
                                                       content: {},
                                                       metadata: {},
                                                       docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY),
                                                       source: {})
    @splitter.split(action_doc)

    doc = Armagh::Document.find(@splitter.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@splitter.doc_id, doc.document_id)
    assert_equal({'DRAFT CONTENT' => true}, doc.content)
    assert_equal({'field' => true, 'draft_meta' => 'bananas'}, doc.metadata)
    assert_false doc.locked?
  end
end
