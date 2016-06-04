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

require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/action/action_manager'

require 'test/unit'
require 'mocha/test_unit'

require 'armagh/actions'

class Action1 < Armagh::Actions::Action; end
class Action2 < Armagh::Actions::Action; end
class ActionShared < Armagh::Actions::Action; end
class TestPublisher < Armagh::Actions::Publish; end
class TestCollector < Armagh::Actions::Collect; end
class TestParser < Armagh::Actions::Parse; end
class TestConsumer < Armagh::Actions::Consume; end
class TestSplitter < Armagh::Actions::CollectionSplitter; end

# Strickly for testing
module Armagh
  module CustomActions
    @actions = []
    def self.set_actions(actions)
      @actions = actions
    end
    def self.defined_actions
      @actions
    end
  end
  module StandardActions
    @actions = []
    def self.set_actions(actions)
      @actions = actions
    end
    def self.defined_actions
      @actions
    end
  end
end

class TestActionManager < Test::Unit::TestCase

  def setup
    @caller = mock('caller')
    @caller.stubs({uuid: '123abc'})
    @logger = mock('logger')
    @config = {}

    @action_manager = Armagh::ActionManager.new(@caller, @logger)

    @action_instances = {
        'action_1' => {
            'input_doc_type' => 'InputDocument1',
            'output_docspecs' => {
                'action_1_output' => {'type' => 'OutputDocument1', 'state' => 'ready'}
            },
            'action_class_name' => 'Action1',
            'parameters' => {}
        },
        'action_2' => {
            'input_doc_type' => 'InputDocument2',
            'output_docspecs' => {
                'action_2_output' => {'type' => 'OutputDocument2', 'state' => 'ready'}
            },
            'action_class_name' => 'Action2',
            'parameters' => {}
        },
        'action_shared' => {
            'input_doc_type' => 'InputDocument1',
            'output_docspecs' => {
                'action_2_output' => {'type' => 'OutputDocument2', 'state' => 'ready'}
            },
            'action_class_name' => 'ActionShared',
            'parameters' => {}
        },
        'publisher' => {
            'doc_type' => 'PublishDocument',
            'action_class_name' => 'TestPublisher',
            'parameters' => {}
        },
        'consumer' => {
            'input_doc_type' => 'InputConsumeDocument',
            'action_class_name' => 'TestConsumer',
            'output_docspecs' => {
                'consume_output' => {'type' => 'ConsumeOutDoc', 'state' => 'ready'}
            },
            'parameters' => {}
        },
        'parser' => {
            'input_doc_type' => 'InputParseDocument',
            'action_class_name' => 'TestParser',
            'output_docspecs' => {
                'parse_output' => {'type' => 'ParseOutDoc', 'state' => 'ready'}
            },
            'parameters' => {}
        },
        'collector' => {
            'input_doc_type' => 'CollectDocument',
            'output_docspecs' => {
                'collect_output_with_split' => {'type' => 'CollectedDocument', 'state' => 'working',
                                     'splitter' => {
                                         'splitter_class_name' => 'TestSplitter',
                                         'parameters' => {}
                                     }},
                'collect_output_no_split' => {'type' => 'CollectedDocumentRaw', 'state' => 'working'}
            },
            'action_class_name' => 'TestCollector',
            'parameters' => {}
        }
    }
    @action_manager.set_available_actions(@action_instances)

    Armagh::CustomActions.set_actions([])
    Armagh::StandardActions.set_actions([])
  end

  def test_get_action_instances
    actions = @action_manager.get_action_names_for_docspec(Armagh::Documents::DocSpec.new('InputDocument2', 'ready'))
    assert_equal(1, actions.length)
    assert_equal('action_2' , actions.first)

    actions = @action_manager.get_action_names_for_docspec(Armagh::Documents::DocSpec.new('InputDocument1', 'ready'))
    assert_equal('action_1' , actions.first)
    assert_equal('action_shared' , actions.last)
  end

  def test_get_action_instances_none
    @logger.expects(:warn).with("No actions defined for docspec 'fake_docspec'")
    assert_empty(@action_manager.get_action_names_for_docspec('fake_docspec'))
  end

  def test_get_action_from_name
    action = @action_manager.get_action('action_shared')
    assert_kind_of(ActionShared, action)
    assert_equal ['action_2_output'], action.output_docspecs.keys
  end

  def test_action_update
    @action_manager.set_available_actions(@action_instances)
    test_get_action_instances
    test_get_action_instances_none
    test_get_action_from_name
  end

  def test_defined_actions_none
    assert_empty Armagh::ActionManager.defined_actions
  end

  def test_available_client_actions
    Armagh::CustomActions.set_actions([Action1])
    assert_equal(1, Armagh::ActionManager.defined_actions.length)
    assert_equal(Action1, Armagh::ActionManager.defined_actions.first)
  end

  def test_available_noragh_actions
    Armagh::StandardActions.set_actions([Action1])
    assert_equal(1, Armagh::ActionManager.defined_actions.length)
    assert_equal(Action1, Armagh::ActionManager.defined_actions.first)
  end

  def test_available_client_and_noragh_actions
    Armagh::CustomActions.set_actions([Action1])
    Armagh::StandardActions.set_actions([Action2])
    available = Armagh::ActionManager.defined_actions
    assert_equal(2, available.length)
    assert_includes(available, Action1)
    assert_includes(available, Action2)
  end

  def test_invalid_action_instance
    @logger.expects(:error).with do |e|
      assert_equal(NameError, e.class)
      assert_match(/Invalid agent configuration.  Could not configure actions.  Exception Details: uninitialized constant (Object::){0,1}BadClass/, e.message)
      true
    end

    actions = {
        'bad_action' => {
            'input_doc_type' => {
                'action_1_input' => {'type' => 'InputDocument1', 'state' => 'ready'}
            },
            'output_docspecs' => {
                'action_1_output' => {'type' => 'OutputDocument1', 'state' => 'ready'}
            },
            'action_class_name' => 'BadClass',
            'config' => {}
        }
    }

    @action_manager.set_available_actions actions
  end

  def test_publish
    action = @action_manager.get_action 'publisher'
    assert_equal({'' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}, action.output_docspecs)
  end

  def test_parse
    action = @action_manager.get_action 'parser'
    assert_equal({'parse_output' => Armagh::Documents::DocSpec.new('ParseOutDoc', Armagh::Documents::DocState::READY)}, action.output_docspecs)
  end

  def test_collect
    action = @action_manager.get_action 'collector'
    assert_equal({
                     'collect_output_no_split' => Armagh::Documents::DocSpec.new('CollectedDocumentRaw', Armagh::Documents::DocState::WORKING),
                     'collect_output_with_split' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::WORKING)
                 }, action.output_docspecs)
  end

  def test_consume
    action = @action_manager.get_action 'consumer'
    assert_equal({'consume_output' => Armagh::Documents::DocSpec.new('ConsumeOutDoc', Armagh::Documents::DocState::READY)}, action.output_docspecs)
  end

  def test_get_action_unknown
    action_name = 'invalid'
    @logger.expects(:error).with("Unknown action '#{action_name}'.  Available actions are #{@action_instances.keys}.")
    @action_manager.get_action action_name
  end

  def test_splitter
    splitter = @action_manager.get_splitter('collector', 'collect_output_with_split')
    assert_equal(Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::WORKING), splitter.output_docspec)
  end

  def test_no_splitter
    assert_nil @action_manager.get_splitter('collector', 'collect_output_no_split')
  end

  def test_non_existent_splitter
    assert_nil @action_manager.get_splitter('invalid', 'invalid')
  end

end