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

require_relative '../test_helpers/coverage_helper'
require_relative '../../lib/action/action_manager'

require 'test/unit'
require 'mocha/test_unit'

require 'logger'
require 'armagh/action'

class Action1 < Armagh::Action; end
class Action2 < Armagh::Action; end
class ActionShared < Armagh::Action; end

# Strickly for testing
module Armagh
  module ClientActions
    @@actions = []
    def self.set_actions(actions)
      @@actions = actions
    end
    def self.available_actions
      @@actions
    end
  end
  module NoraghActions
    @@actions = []
    def self.set_actions(actions)
      @@actions = actions
    end
    def self.available_actions
      @@actions
    end
  end
end

class TestActionManager < Test::Unit::TestCase

  def setup
    @caller = mock('agent')
    @logger = mock('logger')
    @config = {}

    @action_manager = Armagh::ActionManager.new(@caller, @logger)

    @action_instances = {
        'action_1' => {
            'input_doctype' => 'action_1_input',
            'output_doctype' => 'action_1_output',
            'action_class_name' => 'Action1',
            'config' => {}
        },
        'action_2' => {
            'input_doctype' => 'action_2_input',
            'output_doctype' => 'action_2_output',
            'action_class_name' => 'Action2',
            'config' => {}
        },
        'action_shared' => {
            'input_doctype' => 'action_1_input',
            'output_doctype' => 'action_2_output',
            'action_class_name' => 'ActionShared',
            'config' => {}
        }
    }
    @action_manager.set_available_action_instances(@action_instances)

    Armagh::ClientActions.set_actions([])
    Armagh::NoraghActions.set_actions([])
  end

  def test_get_action_instances
    actions = @action_manager.get_action_instance_names('action_2_input')
    assert_equal(1, actions.length)
    assert_equal('action_2' , actions.first)

    actions = @action_manager.get_action_instance_names('action_1_input')
    assert_equal('action_1' , actions.first)
    assert_equal('action_shared' , actions.last)
  end

  def test_get_action_instances_none
    @logger.expects(:warn).with("No actions defined for doctype 'fake_doctype'")
    assert_empty(@action_manager.get_action_instance_names('fake_doctype'))
  end

  def test_get_action_from_name
    action = @action_manager.get_action_from_name('action_shared')
    expected = Armagh::ActionInstance.new('action_shared', 'action_1_input', 'action_2_output', @caller, @logger, @config, 'ActionShared')
    assert_equal(expected , action)
  end

  def test_action_update
    @action_manager.set_available_action_instances(@action_instances)
    test_get_action_instances
    test_get_action_instances_none
    test_get_action_from_name
  end

  def test_available_actions_none
    assert_empty Armagh::ActionManager.available_actions
  end

  def test_available_client_actions
    Armagh::ClientActions.set_actions([Action1])
    assert_equal(1, Armagh::ActionManager.available_actions.length)
    assert_equal(Action1, Armagh::ActionManager.available_actions.first)
  end

  def test_available_noragh_actions
    Armagh::NoraghActions.set_actions([Action1])
    assert_equal(1, Armagh::ActionManager.available_actions.length)
    assert_equal(Action1, Armagh::ActionManager.available_actions.first)
  end

  def test_available_client_and_noragh_actions
    Armagh::ClientActions.set_actions([Action1])
    Armagh::NoraghActions.set_actions([Action2])
    available = Armagh::ActionManager.available_actions
    assert_equal(2, available.length)
    assert_includes(available, Action1)
    assert_includes(available, Action2)
  end

end