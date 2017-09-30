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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/armagh_test/logger'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../lib/armagh'

require 'test/unit'

class TestActionIntegration < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @logger = mock_logger
    Armagh::Actions::GemManager.instance.activate_installed_gems( @logger)
  end

  def test_template_actions
    standard_found_templates =  Armagh::StandardActions::TacballConsume.defined_parameters.find{|p| p.name == 'template'}.options.delete(Armagh::StandardActions::TacballConsume::OPTION_NONE)
    custom_found_templates =  Armagh::CustomActions::TestTemplate.defined_parameters.find{|p| p.name == 'template'}.options
    assert_equal standard_found_templates, custom_found_templates, 'The custom action found different templates than the standard action.'
    assert_not_empty standard_found_templates.select{|t| t.include? 'StandardActions'}, "Templates from StandardActions weren't found."
    assert_not_empty standard_found_templates.select{|t| t.include? 'CustomActions'}, "Templates from CustomActions weren't found."
  end
end
