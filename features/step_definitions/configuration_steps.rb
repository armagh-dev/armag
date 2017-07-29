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

require_relative '../../test/helpers/mongo_support'
require_relative '../../lib/armagh/launcher/launcher'
require_relative '../../lib/armagh/agent/agent'
require_relative '../../lib/armagh/connection'

require 'test/unit/assertions'

require 'time'

When(/^armagh's workflow config is "([^"]*)"$/) do |config|
  @workflow_set ||= Armagh::Actions::WorkflowSet.for_agent(Armagh::Connection.config)
  @workflow = @workflow_set.get_workflow('test_workflow') || @workflow_set.create_workflow({ 'workflow' => { 'name' => 'test_workflow' }})
  @workflow.unused_output_docspec_check = false

  case config
    when 'test_actions'

      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollect',
          {
              'action' => {'name' => 'test_collect'},
              'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
                  'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
              }
          })

      @workflow.create_action_config(
          'Armagh::CustomActions::TestDivide',
          {
              'action' => {'name' => 'test_divider'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestSplit',
          {
              'action' => {'name' => 'test_split'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('SplitDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('SplitOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestPublish',
          {
              'action' => {'name' => 'test_publish'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestConsume',
          {
              'action' => {'name' => 'test_consume'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('ConsumeDocument', Armagh::Documents::DocState::PUBLISHED)},
              'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'bad_publisher'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestBadPublish',
          {
              'action' => {'name' => 'bad_publisher'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

    when 'bad_consumer'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestBadConsume',
          {
              'action' => {'name' => 'bad_consumer'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadConsumeDocument', Armagh::Documents::DocState::PUBLISHED)},
              'output' => {}
          }
      )

    when 'unimplemented_splitter'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestUnimplementedSplit',
          {
              'action' => {'name' => 'unimplemented_splitter'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('UnimplementedSplitInputDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('UnimplementedSplitOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'too_large_collector'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestTooLargeCollect',
          {
              'action' => {'name' => 'too_large_collector'},
              'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('TooLargeCollectOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'too_large_splitter'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestTooLargeSplit',
          {
              'action' => {'name' => 'too_large_splitter'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('TooLargeInputDocType', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('TooLargeSplitOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'edit_current_splitter'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestEditCurrentSplit',
          {
              'action' => {'name' => 'edit_current_splitter'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('EditCurrentInputDocType', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('EditCurrentSplitOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'update_error_splitter'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestUpdateErrorSplit',
          {
              'action' => {'name' => 'update_error_splitter'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('UpdateErrorInputDocType', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('UpdateErrorSplitOutputDocument', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'notify_ops'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestSplitNotifyOps',
          {
              'action' => {'name' => 'notify_ops'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyOpsDocType', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyOpsDocTypeOutput', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'notify_dev'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestSplitNotifyDev',
          {
              'action' => {'name' => 'notify_dev'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyDevDocType', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyDevDocTypeOutput', Armagh::Documents::DocState::WORKING)}
          }
      )

    when 'change_id_publisher'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestChangeIdPublish',
          {
              'action' => {'name' => 'change_id_publisher'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

    when 'non_collector'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestNonCollect',
          {
              'action' => {'name' => 'non_collector'},
              'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('NonDocument', Armagh::Documents::DocState::READY)}
          }
      )

    when 'archive_collector'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollect',
          {
              'action' => {'name' => 'archive_collector'},
              'collect' => {'archive' => true, 'schedule' => '0 0 1 1 0'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
                  'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
              }
          }
      )

    when 'full_workflow'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollect',
          {
              'action' => {'name' => 'test_collect'},
              'collect' => {'archive' => true, 'schedule' => '0 0 1 1 0'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
                  'divide_collected_document' => Armagh::Documents::DocSpec.new('ToDivideDocument', Armagh::Documents::DocState::READY)
              }
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestDivide',
          {
              'action' => {'name' => 'test_divider'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('ToDivideDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestSplit',
          {
              'action' => {'name' => 'test_split'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::READY)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestPublish',
          {
              'action' => {'name' => 'test_publish'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestConsume',
          {
              'action' => {'name' => 'test_consume'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::PUBLISHED)},
              'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::READY)}
          }
      )

    when 'minute_collect'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollect',
          {
              'action' => {'name' => 'test_collect'},
              'collect' => {'archive' => false, 'schedule' => '* * * * *'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
                  'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
              }
          }
      )

    when 'long_collect'
      if @workflow.running?
        @workflow.finish

        retry_count = 0
        begin
          @workflow.stop
        rescue Armagh::Actions::WorkflowActivationError
          if retry_count < 3
            sleep 30
            retry
          else
            raise
          end
        end
      end


      @workflow.update_action_config(
          'Armagh::CustomActions::TestCollect',
          {
              'action' => {'name' => 'test_collect'},
              'collect' => {'archive' => false, 'schedule' => '1 1 1 1 1'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
                  'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
              }
          }
      )


    when 'publisher_notify_good_consumer'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestPublishNotifyDev',
          {
              'action' => {'name' => 'test_publisher_notify_dev'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestConsume',
          {
              'action' => {'name' => 'test_consume'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublishDocument', Armagh::Documents::DocState::PUBLISHED)},
              'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::READY)}
          }
      )

    when 'id_collector'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollectSetsID',
          {
              'action' => {'name' => 'test_collect'},
              'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
              }
          }
      )

    when 'id_publisher'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestPublishSetsID',
          {
              'action' => {'name' => 'test_publish'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

    when 'long_publisher'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestLongPublish',
          {
              'action' => {'name' => 'test_long_publish'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

    when 'publisher_passes_raw_to_consumer'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestPublishPassesRaw',
          {
              'action' => {'name' => 'test_publish_passes_raw'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
              'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
          }
      )

      @workflow.create_action_config(
          'Armagh::CustomActions::TestConsumeReceivesRaw',
          {
              'action' => {'name' => 'test_consume_receives_raw'},
              'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)},
              'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::READY)}
          }
      )

    when 'collect_too_large_raw'
      @workflow.create_action_config(
          'Armagh::CustomActions::TestCollectTooLargeRaw',
          {
              'action' => {'name' => 'test_collect_too_large_raw'},
              'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
              'output' => {
                  'docspec' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
              }
          }
      )

  when 'consume_abort'
    @workflow.create_action_config(
      'Armagh::CustomActions::TestConsumeAbort',
      {
        'action' => {'name' => 'test_consume_abort'},
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('ConsumeDocument', Armagh::Documents::DocState::PUBLISHED)},
      }
    )

  when 'split_abort'
    @workflow.create_action_config(
      'Armagh::CustomActions::TestSplitAbort',
      {
        'action' => {'name' => 'test_split_abort'},
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('SplitDocument', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('SplitDocument2', Armagh::Documents::DocState::READY)}
      }
    )

  when 'publish_abort'
      @workflow.create_action_config(
        'Armagh::CustomActions::TestPublishAbort',
        {
          'action' => {'name' => 'test_publish_abort'},
          'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
          'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
        }
      )

  end


  @workflow.run
  puts 'Running Workflow'
end

When(/^armagh's "([^"]*)" config is$/) do |config_type, table|
  config = table.rows_hash
  config.default = nil

  config['num_agents'] = config['num_agents'].to_i if config['num_agents']
  config['checkin_frequency'] = config['checkin_frequency'].to_i if config['checkin_frequency']
  config['timestamp'] = Time.parse(config['timestamp']) if config['timestamp']

  case config_type
    when 'launcher'
      @launcher_config = Armagh::Launcher.force_update_configuration(Armagh::Connection.config,'127.0.0.1_default', {'launcher' => config})
    when 'agent'
      @agent_config = Armagh::Agent.force_update_configuration(Armagh::Connection.config, 'default', {'agent' => config})
    when 'action'
      @workflow_set ||= Armagh::Actions::WorkflowSet.for_agent(Armagh::Connection.config)
      @workflow = @workflow_set.get_workflow('test_workflow') || @workflow_set.create_workflow({ 'workflow' => { 'name' => 'test_workflow' }})
      @workflow.unused_output_docspec_check = false

      config.merge! ({
        'action' => {'name' => 'test-action', 'active' => true},
        'input' => {'docspec' => 'testdoc:ready'},
        'output' => {'docspec' => 'testdoc:published'},
      })

      if @workflow.running?
        @workflow.finish
        retry_count = 0
        begin
          @workflow.stop
        rescue Armagh::Actions::WorkflowActivationError
          if retry_count < 3
            sleep 30
            retry
          else
            raise
          end
        end
      end

      @action_config = @workflow.update_action_config('Armagh::CustomActions::TestPublish', config)
      @workflow.run
    else
      raise "Unknown config type #{config_type}"
  end
end
