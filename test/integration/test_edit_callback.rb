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

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/logging'
require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/agent/agent'
require_relative '../../lib/armagh/actions/workflow_set'
require_relative '../../lib/armagh/document/document'

require 'test/unit'

require 'mongo'
require 'armagh/actions'

module Armagh
  module StandardActions
    class TestSplitter < Actions::Split
      attr_accessor :doc_id
      attr_accessor :doc_was_new
      attr_reader :doc_class

      def split(_trigger)
        edit(@doc_id) do |doc|
          @doc_class = doc.class
          doc.metadata['field'] = true
          doc.content = {'DRAFT CONTENT' => true}
        end
      end
    end
  end
end

class TestEditCallback < Test::Unit::TestCase

  class TestDocument
    attr_accessor :document_id
  end

  def setup
    MongoSupport.instance.clean_database
    @logger = Armagh::Logging.set_logger('Test::Logger')
    @hostname = 'test_hostname'

    @output_type = 'OutputDocument'
    @output_state = Armagh::Documents::DocState::WORKING

    config_store = []
    workflow_set = Armagh::Actions::WorkflowSet.for_agent( config_store )
    wf = workflow_set.create_workflow( {'workflow' => { 'name' => 'test_wf'}})
    wf.unused_output_docspec_check = false
    wf.create_action_config(
      'Armagh::StandardActions::TestSplitter', 
      { 'action' => { 'name' => 'test_splitter' },
        'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( 'intype', 'ready' )},
        'output' => { 'docspec' => Armagh::Documents::DocSpec.new( @output_type, @output_state )}
      }
    )

    wf.run

    agent_config = Armagh::Agent.create_configuration( config_store, 'default', {} )
    archive_config = Armagh::Utils::Archiver.find_or_create_config(config_store)
    agent = Armagh::Agent.new(agent_config, archive_config, workflow_set, @hostname)

    @splitter = workflow_set.instantiate_action_named( 'test_splitter', agent, @logger, nil )

    doc = TestDocument.new
    doc.document_id = 'some other id'

    agent.instance_variable_set(:@current_doc, doc)

   end

  def test_edit_new
    @splitter.doc_id = 'non_existing_doc_id'
    assert_nil Armagh::Document.find_one_by_document_id_type_state_read_only(@splitter.doc_id, @output_type, @output_state)
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'triggering_id',
                                                       content: {},
                                                       raw: nil,
                                                       metadata: {},
                                                       docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY),
                                                       source: nil,
                                                       document_timestamp: nil,
                                                       title: nil,
                                                       copyright: nil)
    @splitter.split(action_doc)

    assert_equal(Armagh::Documents::ActionDocument, @splitter.doc_class)

    doc = Armagh::Document.find_one_by_document_id_type_state_read_only(@splitter.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@splitter.doc_id, doc.document_id)
    assert_equal({'DRAFT CONTENT' => true}, doc.content)
    assert_equal({'field' => true}, doc.metadata)
    assert_false doc.locked_by_anyone?
  end

  def test_edit_existing
    doc_id = 'existing_doc_id'
    assert_nil Armagh::Document.find_one_by_document_id_type_state_read_only(doc_id, @output_type, @output_state)
    Armagh::Document.create_one_unlocked(type: @output_type,
                            content:{'content' => 123},
                            raw: 'raw',
                            metadata: {'draft_meta' => 'bananas'},
                            pending_actions: [],
                            state: @output_state,
                            document_id: doc_id,
                            collection_task_ids: [],
                            document_timestamp: nil)
    doc = Armagh::Document.find_one_by_document_id_type_state_read_only(doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_false doc.locked_by_anyone?

    @splitter.doc_id = doc_id
    action_doc = Armagh::Documents::ActionDocument.new(document_id: 'triggering_id',
                                                       content: {},
                                                       raw: nil,
                                                       metadata: {},
                                                       docspec: Armagh::Documents::DocSpec.new('TriggerDocument', Armagh::Documents::DocState::READY),
                                                       source: nil,
                                                       document_timestamp: nil,
                                                       title: nil,
                                                       copyright: nil, new: true)
    @splitter.split(action_doc)

    doc = Armagh::Document.find_one_by_document_id_type_state_read_only(@splitter.doc_id, @output_type, @output_state)
    assert_not_nil doc
    assert_equal(@output_type, doc.type)
    assert_equal(@output_state, doc.state)
    assert_equal(@splitter.doc_id, doc.document_id)
    assert_equal({'DRAFT CONTENT' => true}, doc.content)
    assert_equal({'field' => true, 'draft_meta' => 'bananas'}, doc.metadata)
    assert_false doc.locked_by_anyone?
  end
end
