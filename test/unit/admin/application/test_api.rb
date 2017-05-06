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

require_relative '../../../helpers/coverage_helper'
require_relative '../../../helpers/mock_logger'
require_relative '../../../../lib/environment'
Armagh::Environment.init

require_relative '../../../../lib/admin/application/api'
require_relative '../../../../lib/connection'
require 'armagh/actions'

require 'test/unit'
require 'mocha/test_unit'

module Armagh
  module StandardActions
    class TATestCollect < Actions::Collect
      define_parameter name: 'host', type: 'populated_string', required: true, default: 'fredhost', description: 'desc'
    end
  end
end

module Armagh
  module StandardActions
    class TATestPublish < Actions::Publish
    end
  end
end

class TestAdminApplicationAPI < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @logger = mock_logger
    @api = Armagh::Admin::Application::API.instance
    @config_store = []
    Armagh::Connection.stubs(:config).returns(@config_store)
    assert_equal Armagh::Connection.config, @config_store
    @base_values_hash = {
      'action_class_name' => 'Armagh::StandardActions::TATestCollect',

      'output' => {'docspec' => Armagh::Documents::DocSpec.new('dansdoc', Armagh::Documents::DocState::READY)},
      'collect' => {'schedule' => '0 * * * *', 'archive' => false}
    }
  end

  def expected_loaded_action_configs
    [
      {'action' => {'active' => 'true', 'name' => 'action_0'},
       'action_class_name' => 'Armagh::StandardActions::TATestCollect',
       'collect' => {'archive' => 'false', 'schedule' => '0 * * * *'},
       'input' => {'docspec' => '__COLLECT__action_0:ready'},
       'output' => {'docspec' => 'dansdoc:ready'},
       'ta_test_collect' => {'host' => 'somehost'}},
      {'action' => {'active' => 'true', 'name' => 'action_1'},
       'action_class_name' => 'Armagh::StandardActions::TATestCollect',
       'collect' => {'archive' => 'false', 'schedule' => '0 * * * *'},
       'input' => {'docspec' => '__COLLECT__action_1:ready'},
       'output' => {'docspec' => 'dansdoc:ready'},
       'ta_test_collect' => {'host' => 'somehost'}},
      {'action' => {'active' => 'true', 'name' => 'action_2'},
       'action_class_name' => 'Armagh::StandardActions::TATestCollect',
       'collect' => {'archive' => 'false', 'schedule' => '0 * * * *'},
       'input' => {'docspec' => '__COLLECT__action_2:ready'},
       'output' => {'docspec' => 'dansdoc:ready'},
       'ta_test_collect' => {'host' => 'somehost'}},
    ]
  end

  def add_valid_actions(num_configs)
    configs = []

    num_configs.times do |count|
      config = {
        'action_class_name' => 'Armagh::StandardActions::TATestCollect',
        'action' => {'name' => "action_#{count}"},
        'ta_test_collect' => {'host' => 'somehost'},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('dansdoc', Armagh::Documents::DocState::READY)},
        'collect' => {'schedule' => '0 * * * *', 'archive' => false}
      }

      @api.create_action_configuration config

      configs << config
    end

    configs
  end

  def test_create_action_configuration_good
    values_hash = @base_values_hash.merge({
                                            'action' => {'name' => 'fred_the_action'},
                                            'ta_test_collect' => {'host' => 'somehost'}
                                          })
    assert_nothing_raised do
      @api.create_action_configuration(values_hash)
    end
    assert_equal ['fred_the_action'], Armagh::Actions::Action.find_all_configurations(@config_store, :include_descendants => true).collect { |klass, config| config.action.name }
  end

  def test_create_action_already_exists
    values_hash = @base_values_hash.merge({
                                            'action' => {'name' => 'fred_the_action'},
                                            'ta_test_collect' => {'host' => 'somehost'}
                                          })
#    assert_nothing_raised do
      @api.create_action_configuration(values_hash)
 #   end
    assert_equal ['fred_the_action'], Armagh::Actions::Action.find_all_configurations(@config_store, :include_descendants => true).collect { |klass, config| config.action.name }

    e = assert_raises(Armagh::Actions::ConfigurationError) do
      @api.create_action_configuration(values_hash)
    end
    assert_equal 'Action named fred_the_action already exists.', e.message

  end

  def test_create_action_bad_configuration
    values_hash = @base_values_hash.merge({
                                            'action' => {'name' => 'fred_the_action'},
                                            'ta_test_collect' => {'host' => ''}
                                          })

    e = assert_raises(Armagh::Actions::ConfigurationError) do
      @api.create_action_configuration(values_hash)
    end
    assert_equal 'Unable to create configuration Armagh::StandardActions::TATestCollect fred_the_action: ta_test_collect host: type validation failed: string is empty or nil', e.message
  end

  def test_update_action_configuration_good
    values_hash = @base_values_hash.merge({
                                            'action' => {'name' => 'fred_the_action'},
                                            'ta_test_collect' => {'host' => 'somehost'}
                                          })
    assert_nothing_raised do
      @api.create_action_configuration(values_hash)
    end
    stored_configs = Armagh::Actions::Action.find_all_configurations(@config_store, :include_descendants => true)
    assert_equal ['fred_the_action'], stored_configs.collect { |klass, config| config.action.name }
    assert_equal 'somehost', stored_configs.first[1].ta_test_collect.host

    values_hash['ta_test_collect']['host'] = 'someotherhost'
    assert_nothing_raised do
      @api.update_action_configuration(values_hash)
    end
    stored_configs = Armagh::Actions::Action.find_all_configurations(@config_store, :include_descendants => true)
    assert_equal ['fred_the_action'], stored_configs.collect { |klass, config| config.action.name }
    assert_equal 'someotherhost', stored_configs.first[1].ta_test_collect.host
  end

  def test_get_version
    version = @api.get_version
    assert_equal(Armagh::VERSION, version['armagh'])
    assert_not_empty(version['actions']['standard'])
  end

  def test_get_action_configs
    num_configs = 3
    add_valid_actions(num_configs)

    expected_configs = expected_loaded_action_configs
    system_configs = @api.get_action_configs

    assert_equal num_configs, system_configs.length
    assert_equal(expected_configs, system_configs)
  end

  def test_get_action_config
    num_configs = 3
    add_valid_actions(num_configs)

    expected_configs = expected_loaded_action_configs

    assert_equal(expected_configs[0], @api.get_action_config('action_0'))
    assert_equal(expected_configs[1], @api.get_action_config('action_1'))
    assert_equal(expected_configs[2], @api.get_action_config('action_2'))
  end

  def test_get_action_config_none
    assert_nil(@api.get_action_config('no_action'))
  end

  def test_trigger_collect
    collection_trigger = mock('collection trigger')
    collection_trigger.expects(:trigger_individual_collection).with(kind_of(Configh::Configuration))
    Armagh::Utils::CollectionTrigger.expects(:new).returns(collection_trigger)
    name = add_valid_actions(1).first.dig('action', 'name')
    assert_true @api.trigger_collect(name)
  end

  def test_trigger_collect_none
    assert_false@api.trigger_collect('no_action')
  end

  def test_trigger_collect_not_collect
    config = {
      'action_class_name' => 'Armagh::StandardActions::TATestPublish',
      'action' => {'name' => 'testpublish'},
      'input' => {'docspec' => Armagh::Documents::DocSpec.new('doc1', Armagh::Documents::DocState::READY)},
      'output' => {'docspec' => Armagh::Documents::DocSpec.new('doc1', Armagh::Documents::DocState::PUBLISHED)},
    }

    @api.create_action_configuration config
    assert_false @api.trigger_collect('testpublish')
  end
end