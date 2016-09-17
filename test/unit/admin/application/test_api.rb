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

require_relative '../../../helpers/coverage_helper'

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
      define_output_docspec 'collected_document', 'Docs collected from source'
      define_parameter name: 'host', type: 'populated_string', required: true, default: 'fredhost', description: 'desc'
    end
  end
end

class TestAdminApplicationAPI < Test::Unit::TestCase

  def setup
    @logger = mock
    @api = Armagh::Admin::Application::API.instance
    @config_store = []
    Armagh::Connection.stubs( :config ).returns( @config_store )
    @base_values_hash = { 
      'output' => { 'collected_document' => Armagh::Documents::DocSpec.new( 'dansdoc', Armagh::Documents::DocState::READY)},
      'collect' => { 'schedule' => '0 * * * *'}
    }
  end
  
  def test_create_action_configuration_good
    values_hash = @base_values_hash.merge( {
      'action' => { 'name' => 'fred_the_action' },
      'tatestcollect' => { 'host' => 'somehost' }
    })
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    assert_equal ['fred_the_action'], Armagh::Actions::Action.find_all_configurations( @config_store, :include_descendants => true ).collect{ |klass,config| config.action.name }
  end

  def test_create_action_already_exists
    values_hash = @base_values_hash.merge( {
      'action' => { 'name' => 'fred_the_action' },
      'tatestcollect' => { 'host' => 'somehost' }
    })
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    assert_equal ['fred_the_action'], Armagh::Actions::Action.find_all_configurations( @config_store, :include_descendants => true ).collect{ |klass,config| config.action.name }
    
    e = assert_raises( Armagh::Actions::ConfigurationError ) do
      @api.create_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    assert_equal 'Action named fred_the_action already exists.', e.message
    
  end

  def test_create_action_bad_configuration 
    values_hash = @base_values_hash.merge( {
      'action' => { 'name' => 'fred_the_action' },
      'tatestcollect' => { 'host' => '' }
    })
    
    e = assert_raises( Armagh::Actions::ConfigurationError ) do
      @api.create_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    assert_equal 'Unable to create configuration Armagh::StandardActions::TATestCollect fred_the_action: tatestcollect host: type validation failed: string is empty or nil', e.message
  end
  
  def test_update_action_configuration_good
    values_hash = @base_values_hash.merge( {
      'action' => { 'name' => 'fred_the_action' },
      'tatestcollect' => { 'host' => 'somehost' }
    })
    assert_nothing_raised do
      @api.create_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    stored_configs = Armagh::Actions::Action.find_all_configurations( @config_store, :include_descendants => true )
    assert_equal ['fred_the_action'], stored_configs.collect{ |klass,config| config.action.name }
    assert_equal 'somehost', stored_configs.first[1].tatestcollect.host
    
    values_hash[ 'tatestcollect' ][ 'host' ] = 'someotherhost' 
    assert_nothing_raised do
      @api.update_action_configuration( 'Armagh::StandardActions::TATestCollect', values_hash )
    end
    stored_configs = Armagh::Actions::Action.find_all_configurations( @config_store, :include_descendants => true )
    assert_equal ['fred_the_action'], stored_configs.collect{ |klass,config| config.action.name }
    assert_equal 'someotherhost', stored_configs.first[1].tatestcollect.host
    
  end
end