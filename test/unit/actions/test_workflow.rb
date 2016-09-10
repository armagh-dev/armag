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
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/action/workflow'

module Armagh
  module StandardActions
    
    DS_READY     = Armagh::Documents::DocState::READY
    DS_PUBLISHED = Armagh::Documents::DocState::PUBLISHED
    
    class TWTestCollect < Actions::Collect

      define_output_docspec 'collected_a', 'collected documents of first type'
      define_output_docspec 'collected_b', 'collected documents of second type'
      
      def self.make_test_config( store:, action_name:, collected_a_doctype:, collected_b_doctype: )
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => {},
          'output' => {
            'collected_a' => Armagh::Documents::DocSpec.new( collected_a_doctype, DS_READY ),
            'collected_b' => Armagh::Documents::DocSpec.new( collected_b_doctype, DS_READY )
          }
        })
      end
    end

    class TWTestDivide < Actions::Divide
      
      define_output_docspec 'divided', 'divided documents'
      
      def self.make_test_config( store:, action_name:, input_doctype:, divided_doctype:)
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
          'output' => { 'divided' => Armagh::Documents::DocSpec.new( divided_doctype, DS_READY ) }
        })
      end   
    end
    
    class TWTestSplit < Actions::Split
      
      define_output_docspec 'single', 'single instance'
      
      def self.make_test_config( store:, action_name:, input_doctype:, single_doctype: )
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
          'output' => { 'single'  => Armagh::Documents::DocSpec.new( single_doctype, DS_READY )}
        })
      end   
    end
    
    class TWTestPublish < Actions::Publish
      
      define_output_docspec 'published', 'published documents'
      
      def self.make_test_config( store:, action_name:, published_doctype: )
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec'   => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
          'output' => { 'published' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        })
      end
    end
    
    class TWTestPublish2 < Actions::Publish
      
      define_output_docspec 'published2', 'published docs'
      
      def self.make_test_config( store:, action_name:, published_doctype: )
        create_configuration( store, action_name, {
          'input' => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
          'output' => { 'published2' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        })
      end
    end
    
    class TWTestConsume < Actions::Consume
              
      def self.make_test_config( store:, action_name:, input_doctype: )
        create_configuration( store, action_name, {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_PUBLISHED) }
        })
      end
    end
    end
end

class TestWorkflow < Test::Unit::TestCase
  
  def setup
    @config_store = []
    
    @aasmod = Armagh::StandardActions
    
    @test_configs_fred_flow = {
      "collect_freddocs_from_source" => 
        @aasmod::TWTestCollect.make_test_config( 
          store: @config_store,
          action_name: 'collect_freddocs_from_source',
          collected_a_doctype: 'a_freddoc',
          collected_b_doctype: 'b_freddocs_aggr_big'
      ),
      "divide_b_freddocs" =>
        @aasmod::TWTestDivide.make_test_config(
          store: @config_store,
          action_name: 'divide_b_freddocs',
          input_doctype: 'b_freddocs_aggr_big',
          divided_doctype: 'b_freddocs_aggr'
      ),
      "split_b_freddocs" =>
        @aasmod::TWTestSplit.make_test_config(
          store: @config_store,
          action_name: 'split_b_freddocs',
          input_doctype: 'b_freddocs_aggr',
          single_doctype: 'b_freddoc'
      ),
      "publish_a_freddocs" =>
        @aasmod::TWTestPublish.make_test_config(
          store: @config_store,
          action_name: 'publish_a_freddocs', 
          published_doctype: 'a_freddoc'     
      ),
      "publish_b_freddocs" =>
        @aasmod::TWTestPublish.make_test_config(
          store: @config_store,
          action_name: 'publish_b_freddocs',
          published_doctype: 'b_freddoc'
      ),
      "consume_a_freddoc_1" =>
        @aasmod::TWTestConsume.make_test_config(
          store: @config_store,
          action_name: 'consume_a_freddoc_1',
          input_doctype: 'a_freddoc' 
      ),
      "consume_a_freddoc_2" =>
        @aasmod::TWTestConsume.make_test_config(
          store: @config_store,
          action_name: 'consume_a_freddoc_2',
          input_doctype: 'a_freddoc' 
      ),
      "consume_b_freddoc_1" =>
        @aasmod::TWTestConsume.make_test_config(
          store: @config_store,
          action_name: 'consume_b_freddoc_1',
          input_doctype: 'b_freddoc' 
      )
    }
    
    @logger = mock
    @caller = mock
    @a = Armagh::Actions
    @d = Armagh::Documents
    
  end
  
  def teardown
  end
  
  def test_overlapping_docspecs
    
    assert_equal [ 'published' ], @aasmod::TWTestPublish.defined_parameters.collect{ |p| p.name if p.group == 'output' }.compact
    assert_equal [ 'published2' ], @aasmod::TWTestPublish2.defined_parameters.collect{ |p| p.name if p.group == 'output' }.compact
  end
  
  def test_fred_flow
    
    workflow = nil
    assert_nothing_raised {
      workflow = @a::Workflow.new( @logger, @config_store )
    }
    @test_configs_fred_flow.each do |action_name, config|
      a = workflow.get_action( action_name, @caller, @logger )
      assert_not_nil a
      assert_equal config.input.docspec, a.config.input.docspec
    end
  end    
  
  def test_loopy_flow
    
    @loopy_flow = @test_configs_fred_flow
    @loopy_flow[ 'backpath' ] = @aasmod::TWTestSplit.make_test_config(
      store: @config_store,
      action_name: 'backpath',
      input_doctype: 'b_freddoc',
      single_doctype: 'b_freddocs_aggr'
    )
    
    e = assert_raises( @a::ConfigurationError ) {
      @a::Workflow.new( @logger, @config_store )
    }
    assert_equal "Action configuration has a cycle.", e.message
    
  end
  
  def test_get_action_names_for_docspec
    workflow = nil
    assert_nothing_raised {
      workflow = @a::Workflow.new( @logger, @config_store )
    }
    want_docspec = @d::DocSpec.new( 'a_freddoc', @d::DocState::PUBLISHED )
    action_names = workflow.get_action_names_for_docspec( want_docspec )
    assert_equal [ 'consume_a_freddoc_1', 'consume_a_freddoc_2' ], action_names.sort
  end
end