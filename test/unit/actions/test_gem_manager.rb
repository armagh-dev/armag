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

require_relative '../../helpers/coverage_helper'
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/actions/gem_manager'

class TestGemManager < Test::Unit::TestCase
  
  def setup
    @logger = mock
    @cloned_gem_manager = Armagh::Actions::GemManager.clone
  end
  
  def teardown
  end
  
  def test_activate_installed_gems
    Gem.expects(:try_activate).with('armagh/standard_actions').returns(true).at_least_once
    Gem.expects(:try_activate).with('armagh/custom_actions').returns(false).at_least_once

    @logger.expects(:info).with { |s| s.start_with? 'Using standard:' }
    @logger.expects(:ops_warn).with("CustomActions gem is not deployed. These actions won't be available.")

    action_versions = @cloned_gem_manager.instance.activate_installed_gems(@logger)
    assert_equal({'standard' => Armagh::StandardActions::VERSION}, action_versions)
  end
end
