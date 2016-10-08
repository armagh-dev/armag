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
require_relative '../../../lib/connection'

module Armagh
  module StandardActions
    
    DS_READY     = Armagh::Documents::DocState::READY
    DS_PUBLISHED = Armagh::Documents::DocState::PUBLISHED
    
    class TWTestCollect < Actions::Collect

      define_output_docspec 'collected_a', 'collected documents of first type'
      define_output_docspec 'collected_b', 'collected documents of second type'
      
      define_parameter name:'count', required: true, type: 'integer', default: 6, description: 'desc'
      
      def self.make_config_values( action_name:, collected_a_doctype:, collected_b_doctype: )
        {
          'action' => { 'name' => action_name, 'active' => true },
          'collect' => { 'schedule' => '0 * * * *', 'archive' => false },
          'input'  => {},
          'output' => {
            'collected_a' => Armagh::Documents::DocSpec.new( collected_a_doctype, DS_READY ),
            'collected_b' => Armagh::Documents::DocSpec.new( collected_b_doctype, DS_READY )
          }
        }
      end
    end

    class TWTestDivide < Actions::Divide
      
      define_output_docspec 'divided', 'divided documents'
      
      def self.make_config_values( action_name:, input_doctype:, divided_doctype:)
        {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
          'output' => { 'divided' => Armagh::Documents::DocSpec.new( divided_doctype, DS_READY ) }
        }
      end   
    end
    
    class TWTestSplit < Actions::Split
      
      define_output_docspec 'single', 'single instance'
      
      def self.make_config_values( action_name:, input_doctype:, single_doctype: )
        {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
          'output' => { 'single'  => Armagh::Documents::DocSpec.new( single_doctype, DS_READY )}
        }
      end   
    end
    
    class TWTestPublish < Actions::Publish
      
      define_output_docspec 'published', 'published documents'
      
      def self.make_config_values( action_name:, published_doctype: )
        {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec'   => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
          'output' => { 'published' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        }
      end
    end
    
    class TWTestPublish2 < Actions::Publish
      
      define_output_docspec 'published2', 'published docs'
      
      def self.make_config_values( action_name:, published_doctype: )
        {
          'input' => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
          'output' => { 'published2' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        }
      end
    end
    
    class TWTestConsume < Actions::Consume
              
      def self.make_config_values( action_name:, input_doctype: )
        {
          'action' => { 'name' => action_name, 'active' => true },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_PUBLISHED) }
        }
      end
    end
  end
end

class TestWorkflow < Test::Unit::TestCase
  
  def setup
    @config_store = []
    @logger = mock
    @caller = mock
  
    @test_action_setup = {
      'Armagh::StandardActions::TWTestCollect' => [
        { action_name: 'collect_freddocs_from_source',
          collected_a_doctype: 'a_freddoc',
          collected_b_doctype: 'b_freddocs_aggr_big'
        }
      ],
      
      'Armagh::StandardActions::TWTestDivide' => [
        { action_name: 'divide_b_freddocs',
          input_doctype: 'b_freddocs_aggr_big',
          divided_doctype: 'b_freddocs_aggr'
        }
      ],
      
      'Armagh::StandardActions::TWTestSplit' => [
        { action_name: 'split_b_freddocs',
          input_doctype: 'b_freddocs_aggr',
          single_doctype: 'b_freddoc'
        }
      ],
      
      'Armagh::StandardActions::TWTestPublish' => [
         { action_name: 'publish_a_freddocs', 
           published_doctype: 'a_freddoc'    
         }, 
         { action_name: 'publish_b_freddocs',
           published_doctype: 'b_freddoc'
         }
      ],
      
      'Armagh::StandardActions::TWTestConsume' => [
         { action_name: 'consume_a_freddoc_1',
           input_doctype: 'a_freddoc' 
         },
         { action_name: 'consume_a_freddoc_2',
           input_doctype: 'a_freddoc' 
         },
         { action_name: 'consume_b_freddoc_1',
           input_doctype: 'b_freddoc' 
        }
      ]
    }
 
    @state_coll = mock
    Armagh::Connection.stubs( :config ).returns( @state_coll )
  end
  
  def teardown
  end
  
  def test_overlapping_docspecs
    
    assert_equal [ 'published' ], Armagh::StandardActions::TWTestPublish.defined_parameters.collect{ |p| p.name if p.group == 'output' }.compact
    assert_equal [ 'published2' ], Armagh::StandardActions::TWTestPublish2.defined_parameters.collect{ |p| p.name if p.group == 'output' }.compact
  end

  def do_add_configs
      
    workflow = nil
    assert_nothing_raised {
      workflow = Armagh::Actions::Workflow.new( @logger, @config_store )
    }
    @test_action_setup.each do |action_class_name, setup_values_list|
      setup_values_list.each do |setup_values|
        assert_nothing_raised do 
          c = workflow.create_action( action_class_name, eval(action_class_name).make_config_values( **setup_values ))
        end
      end
    end
    workflow
  end
  
  def test_add_configs
    
    workflow = do_add_configs
    assert_equal [ 'consume_a_freddoc_1', 'consume_a_freddoc_2'], workflow.get_action_names_for_docspec( Armagh::Documents::DocSpec.new( 'a_freddoc', 'published' ))
  end  

  def test_loopy_flow
    
    workflow = do_add_configs
    
    e = assert_raises( Armagh::Actions::ConfigurationError ) {
      workflow.create_action( 
        'Armagh::StandardActions::TWTestSplit',
        Armagh::StandardActions::TWTestSplit.make_config_values( 
          action_name: 'backpath',
          input_doctype: 'b_freddoc',
          single_doctype: 'b_freddocs_aggr'
        )
      )
    }
    assert_equal "Action configuration has a cycle.", e.message
    
  end

  def test_update_config
    workflow = do_add_configs

    new_config = Armagh::StandardActions::TWTestCollect.make_config_values(
      action_name: 'collect_freddocs_from_source',
      collected_a_doctype: 'a_freddoc',
      collected_b_doctype: 'b_freddocs_aggr_big'
    )
    new_config[ 'twtestcollect' ] ||= {}
    new_config[ 'twtestcollect' ][ 'count' ] = 19
 
    workflow.update_action( 
      'Armagh::StandardActions::TWTestCollect',
      new_config
    )
    
  end
  
  def test_instantiate_action
    
    workflow = do_add_configs
    
    paf = workflow.instantiate_action( 'publish_a_freddocs', @caller, @logger, @state_coll )
    assert paf.is_a?( Armagh::StandardActions::TWTestPublish )
    assert_equal 'a_freddoc', paf.config.input.docspec.type
  end
  
end
