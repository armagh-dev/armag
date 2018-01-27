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

require 'armagh/documents'
require 'armagh/actions'

module Armagh
  module StandardActions

    DS_READY     = Armagh::Documents::DocState::READY
    DS_PUBLISHED = Armagh::Documents::DocState::PUBLISHED

    class TWTestCollect < Actions::Collect

      define_output_docspec 'docspec2', 'collected documents of second type'

      define_parameter name:'count', required: true, type: 'integer', default: 6, description: 'desc'

      def self.make_config_values(action_name:, collected_a_doctype:, collected_b_doctype:)
        {
            'action' => { 'name' => action_name },
            'collect' => { 'schedule' => '7 * * * *', 'archive' => false },
            'input'  => {},
            'output' => {
                'docspec' => Armagh::Documents::DocSpec.new( collected_a_doctype, DS_READY ),
                'docspec2' => Armagh::Documents::DocSpec.new( collected_b_doctype, DS_READY )
            }
        }
      end
    end

    class TWTestDivide < Actions::Divide

      def self.make_config_values( action_name:, input_doctype:, divided_doctype: )
        {
            'action' => { 'name' => action_name },
            'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
            'output' => { 'docspec' => Armagh::Documents::DocSpec.new( divided_doctype, DS_READY ) }
        }
      end
    end

    class TWTestSplit < Actions::Split

      define_output_docspec 'docspec', 'single instance'

      def self.make_config_values( action_name:, input_doctype:, single_doctype: )
        {
            'action' => { 'name' => action_name },
            'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_READY ) },
            'output' => { 'docspec'  => Armagh::Documents::DocSpec.new( single_doctype, DS_READY )}
        }
      end
    end

    class TWTestPublish < Actions::Publish

      def self.make_config_values( action_name:, published_doctype: )
        {
            'action' => { 'name' => action_name },
            'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
            'output' => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        }
      end
    end

    class TWTestPublish2 < Actions::Publish

      def self.make_config_values( action_name:, published_doctype: )
        {
            'action' => { 'name' => action_name },
            'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_READY ) },
            'output' => { 'docspec' => Armagh::Documents::DocSpec.new( published_doctype, DS_PUBLISHED ) }
        }
      end
    end

    class TWTestConsume < Actions::Consume

      define_output_docspec 'docspec', 'the output from consume'

      def self.make_config_values( action_name:, input_doctype:, output_doctype: )
        val = {
            'action' => { 'name' => action_name },
            'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_PUBLISHED) },
            'output'  => { 'docspec' => Armagh::Documents::DocSpec.new( output_doctype, DS_READY) }

        }
        if output_doctype
          val[ 'output' ] = {}
          val[ 'output' ][ 'docspec' ] = Armagh::Documents::DocSpec.new( output_doctype, DS_READY)
        end

        val
      end
    end

    class TWTestConsumeNilOutput < Actions::Consume

      def self.make_config_values(action_name:, input_doctype:)
        {
          'action' => { 'name' => action_name },
          'input'  => { 'docspec' => Armagh::Documents::DocSpec.new( input_doctype, DS_PUBLISHED) }
        }
      end
    end
  end
end

module WorkflowGeneratorHelper

  def self.workflow_actions_config_values_no_divide( workflow_name )
    [
      [ 'Armagh::StandardActions::TWTestCollect',
        Armagh::StandardActions::TWTestCollect.make_config_values(
          action_name: "collect_#{workflow_name}docs_from_source",
          collected_a_doctype: "a_#{workflow_name}doc",
          collected_b_doctype: "b_#{workflow_name}docs_aggr"
        )
      ],

      [ 'Armagh::StandardActions::TWTestSplit',
        Armagh::StandardActions::TWTestSplit.make_config_values(
          action_name: "split_b_#{workflow_name}docs",
          input_doctype: "b_#{workflow_name}docs_aggr",
          single_doctype: "b_#{workflow_name}doc"
        )
      ],

      [ 'Armagh::StandardActions::TWTestPublish',
        Armagh::StandardActions::TWTestPublish.make_config_values(
          action_name: "publish_a_#{workflow_name}docs",
          published_doctype: "a_#{workflow_name}doc"
        )
      ],

      [ 'Armagh::StandardActions::TWTestPublish',
        Armagh::StandardActions::TWTestPublish.make_config_values(
            action_name: "publish_b_#{workflow_name}docs",
            published_doctype: "b_#{workflow_name}doc"
        )
      ],

      [ 'Armagh::StandardActions::TWTestConsume',
        Armagh::StandardActions::TWTestConsume.make_config_values(
          action_name: "consume_a_#{workflow_name}doc_1",
          input_doctype: "a_#{workflow_name}doc",
          output_doctype: "a_#{workflow_name}doc_out"
        )
      ],

      [ 'Armagh::StandardActions::TWTestConsume',
        Armagh::StandardActions::TWTestConsume.make_config_values(
          action_name: "consume_a_#{workflow_name}doc_2",
          input_doctype: "a_#{workflow_name}doc",
          output_doctype: "a_#{workflow_name}doc_out"
        )
      ],

      [ 'Armagh::StandardActions::TWTestConsume',
        Armagh::StandardActions::TWTestConsume.make_config_values(
          action_name: "consume_b_#{workflow_name}doc_1",
          input_doctype: "b_#{workflow_name}doc",
          output_doctype: "b_#{workflow_name}consume_out_doc"
        )
      ]
    ]
  end

  def self.workflow_actions_config_values_with_divide( workflow_name )

    big_doc_docspec = Armagh::Documents::DocSpec.new( "b_#{workflow_name}docs_aggr_big", Armagh::StandardActions::DS_READY )
    configs = workflow_actions_config_values_no_divide( workflow_name )

    configs.find{ |class_name,config_values|
      config_values['action']['name'] == "collect_#{workflow_name}docs_from_source"
    }[1][ 'output' ][ 'docspec2' ] = big_doc_docspec

    configs << [
      'Armagh::StandardActions::TWTestDivide',
      Armagh::StandardActions::TWTestDivide.make_config_values(
        action_name: "divide_b_#{workflow_name}docs",
        input_doctype: "b_#{workflow_name}docs_aggr_big",
        divided_doctype: "b_#{workflow_name}docs_aggr"
      )
    ]

    configs.find{ |class_name,config_values|
      config_values['action']['name'] == "split_b_#{workflow_name}docs"
    }[1][ 'input' ][ 'docspec' ] = big_doc_docspec

    configs
  end

  def self.workflow_actions_config_values_with_no_unused_output(workflow_name)
    consume_class = "Armagh::StandardActions::TWTestConsume"
    # start with the usual array of actions
    configs = workflow_actions_config_values_no_divide(workflow_name)
    # delete the output docspec from the consumers
    configs.each{ |class_name, values| values.delete("output") if class_name == consume_class }
    # change the consumer actions to a consumer class that expects no output docspec
    configs.map{ |class_name, values| class_name == consume_class ? [ class_name + "NilOutput", values ] : [ class_name, values ] }
  end

  def self.break_array_config_store( config_store, workflow_name)
    wf_hash = config_store.find{ |c| c['name'] == "collect_#{workflow_name}docs_from_source" }
    wf_hash['values']['output'].delete 'docspec'

    wf_hash = config_store.find{ |c| c['name'] == "consume_b_#{workflow_name}doc_1" }
    wf_hash['values']['input'].delete 'docspec'
  end

  def self.break_workflow_actions_config( workflow_actions_config_values, workflow_name )
    wf_hash = workflow_actions_config_values.find{ |_k,c| c['action']['name'] == "collect_#{workflow_name}docs_from_source"}
    wf_hash[1]['output'].delete 'docspec'

    wf_hash = workflow_actions_config_values.find{ |_k,c| c['action']['name'] == "consume_b_#{workflow_name}doc_1"}
    wf_hash[1]['input'].delete 'docspec'
  end

  def self.force_duplicate_action_name( workflow_actions_config_values, workflow_name )
    wf_hash = workflow_actions_config_values.find{ |_k,c| c['action']['name'] == "consume_b_#{workflow_name}doc_1"}
    wf_hash[1]['action']['name'] = "consume_a_#{workflow_name}doc_1"
  end

  def self.force_cycle( workflow_actions_config_values, workflow_name )
    split_hash = workflow_actions_config_values.find{ |_k,c| c['action']['name'] == "split_b_#{workflow_name}docs"}
    consume_hash = workflow_actions_config_values.find{ |_k,c| c['action']['name'] == "consume_b_#{workflow_name}doc_1"}
    split_hash[1]['input']['docspec'] = consume_hash[1]['output']['docspec']
  end
end
