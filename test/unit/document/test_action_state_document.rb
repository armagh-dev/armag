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

require_relative '../../helpers/coverage_helper'
require_relative '../../helpers/armagh_test'
require_relative '../../../lib/armagh/document/action_state_document'

require 'test/unit'
require 'mocha/test_unit'

class TestActionStateDocument < Test::Unit::TestCase

  def setup
    @collection = mock
    Armagh::Connection.stubs( action_state: @collection )
    @agent = mock
    @agent.stubs( signature: 'iami', running?: true )
    @doc = Armagh::ActionStateDocument.send(:new)
  end

  def test_defaults
    assert_equal @collection,Armagh::ActionStateDocument.default_collection
    assert_equal 60, Armagh::ActionStateDocument.default_lock_wait_duration
    assert_equal 120, Armagh::ActionStateDocument.default_lock_hold_duration
  end

  def test_validate_content
    assert_nothing_raised do
      @doc.content = { 'hi' => 'there' }
    end
    assert_raises Armagh::ActionStateDocument::ContentError do
      @doc.content = 'oops'
    end
  end

  def test_find_or_create_doesnt_exist
    action_name = 'my_action'
    Armagh::ActionStateDocument.expects( :find_one_locked).with( {'action_name' => action_name}, @agent, collection: @collection, lock_wait_duration: 60, lock_hold_duration: 1000 ).returns( nil )
    Armagh::ActionStateDocument.expects( :create_one_locked ).with( {'action_name' => action_name}, @agent, collection: @collection, lock_hold_duration: 1000 )
    Armagh::ActionStateDocument.find_or_create_one_by_action_name_locked( action_name, @agent, lock_hold_duration: 1000 )
  end

  def test_find_or_create_exists
    action_name = 'my_action'
    state_doc = Armagh::ActionStateDocument.send(:new, { 'action_name' => action_name } )
    Armagh::ActionStateDocument.expects( :find_one_locked).with( {'action_name' => action_name}, @agent, collection: @collection, lock_wait_duration: 60, lock_hold_duration: 1000 ).returns( state_doc  )
    Armagh::ActionStateDocument.find_or_create_one_by_action_name_locked( action_name, @agent, lock_hold_duration: 1000 )
  end

end
