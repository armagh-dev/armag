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

require_relative '../../../helpers/coverage_helper'
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../../lib/armagh/actions/utility_actions/utility_action'

require 'armagh/actions'


module Armagh
  module Actions
    module UtilityActions
      class SubUtilityAction < Armagh::Actions::UtilityAction; end
    end
  end
end

class TestUtilityAction < Test::Unit::TestCase

  def setup
    @caller = mock
    @collection = mock
    @config_store = []
  end

  def test_good_config_cron
    config = nil
    assert_nothing_raised do
      config = Armagh::Actions::UtilityActions::SubUtilityAction.create_configuration(@config_store, 'util', {
        'action' => {'name' => 'mysubutility', 'workflow' => 'wf'},
        'utility' => {'schedule' => '*/10 * * * *'}
      })
    end

    @utility_action = Armagh::Actions::UtilityActions::SubUtilityAction.new(@caller, 'logger_name', config)
    assert_equal 'mysubutility',@utility_action.config.action.name
    assert_equal '*/10 * * * *', @utility_action.config.utility.schedule
    assert @utility_action.config.action.active

  end

  def test_good_config_no_cron
    config = nil
    assert_nothing_raised do
      config = Armagh::Actions::UtilityActions::SubUtilityAction.create_configuration(@config_store, 'util', {
          'action' => {'name' => 'mysubutilityaction', 'workflow' => 'wf'}
      })
    end
    @utility_action = Armagh::Actions::UtilityActions::SubUtilityAction.new(@caller, 'logger_name', config)
    assert_equal 'mysubutilityaction',@utility_action.config.action.name
    assert_nil @utility_action.config.utility.schedule
    assert @utility_action.config.action.active
    assert_equal '__UTILITY__mysubutilityaction:ready', @utility_action.config.input.docspec.to_s
  end

  def test_bad_config_bad_cron
    expected_error = Configh::ConfigInitError.new( "Unable to create configuration for 'Armagh::Actions::UtilityActions::SubUtilityAction' named 'util' because: \n    Schedule 'notacron' is not valid cron syntax.")
    assert_raises expected_error do
    config = Armagh::Actions::UtilityActions::SubUtilityAction.create_configuration(@config_store, 'util', {
        'action' => {'name' => 'mysubutilityaction', 'workflow' => 'wf'},
        'utility' => {'schedule' => 'notacron'}
    })
    end
  end

  def test_no_default_input_type
    assert_raises Armagh::Actions::ConfigurationError.new('You cannot define default input types for utilities') do
      Armagh::Actions::UtilityActions::SubUtilityAction.define_default_input_type 'blah'
    end
  end

  def test_run_not_implemented
    config = Armagh::Actions::UtilityActions::SubUtilityAction.create_configuration(@config_store, 'util', {
        'action' => {'name' => 'mysubutility', 'workflow' => 'wf'}
    })

    @utility_action = Armagh::Actions::UtilityActions::SubUtilityAction.new(@caller, 'logger_name', config)
    expected_error = Armagh::Actions::Errors::ActionMethodNotImplemented.new("Utility actions must overwrite the run method.")
    assert_raises expected_error do
      @utility_action.run
    end

  end

  def test_defined_utilities
    assert Armagh::Actions::UtilityAction.defined_utilities.include?(Armagh::Actions::UtilityActions::SubUtilityAction)
  end
end
