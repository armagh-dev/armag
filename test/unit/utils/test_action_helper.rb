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
require_relative '../../../lib/armagh/utils/action_helper'

require 'armagh/actions'

require 'test/unit'
require 'mocha/test_unit'

class TestAction < Armagh::Actions::Collect
end

class SuperTestAction < TestAction
end

class TestActionHelper < Test::Unit::TestCase
  def setup
    Armagh::Actions.stubs(:defined_actions).returns([TestAction, SuperTestAction])
  end

  def test_get_action_super
    assert_equal 'Collect', Armagh::Utils::ActionHelper.get_action_super(TestAction)
  end

  def test_get_action_super_super
    assert_equal 'Collect', Armagh::Utils::ActionHelper.get_action_super(SuperTestAction)
  end

  def test_get_action_super_nil
    e = Armagh::Utils::ActionHelper::ActionClassError.new('NilClass is not a known action type.')
    assert_raise(e){ Armagh::Utils::ActionHelper.get_action_super(nil)}
  end

  def test_get_action_super_nonaction
    e = Armagh::Utils::ActionHelper::ActionClassError.new('Hash is not a known action type.')
    assert_raise(e){ Armagh::Utils::ActionHelper.get_action_super(Hash)}
  end
end