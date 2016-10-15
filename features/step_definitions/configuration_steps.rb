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

require_relative '../../test/helpers/mongo_support'
require_relative '../../lib/launcher/launcher'
require_relative '../../lib/agent/agent'
require_relative '../../lib/connection'

require 'test/unit/assertions'

require 'log4r'
require 'time'

When(/^armagh's workflow config is "([^"]*)"$/) do |config|
  case config
    when 'test_actions'
      Armagh::CustomActions::TestCollector.create_configuration(Armagh::Connection.config, 'test_collect', {
        'action' => { 'name' => 'test_collect'},
        'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY) # TODO HOW TO SETUP DIVIDER?
        }
      })
  end
end

When(/^armagh's "([^"]*)" config is$/) do |config_type, table|
  config = table.rows_hash
  config.default = nil

  config['num_agents'] = config['num_agents'].to_i if config['num_agents']
  config['checkin_frequency'] = config['checkin_frequency'].to_i if config['checkin_frequency']
  config['timestamp'] = Time.parse(config['timestamp']) if config['timestamp']

  if config['available_actions']
    specified_actions = config['available_actions'].split(/\s*,\s*/)
    available_actions = {}

    if specified_actions.include? 'test_actions'
      Armagh::CustomActions::TestCollector.create_configuration(Armagh::Connection.config, 'test_collect', {
        'action' => { 'name' => 'test_collect'},
        'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY) # TODO HOW TO SETUP DIVIDER?
        }
      })


      test_actions = {
          'test_collect' => {
              'action_class_name' => 'Armagh::CustomActions::TestCollector',
              'input_doc_type' => 'CollectDocument',

              'output_docspecs' => {
                  'collected_document' => {'type' => 'CollectedDocument', 'state' => 'ready'},
                  'divide_collected_document' => {'type' => 'DivideCollectedDocument', 'state' => 'ready',
                                                 'divider' => {
                                                     'divider_class_name' => 'Armagh::CustomActions::TestDivider',
                                                     'parameters' => {}
                                                 }
                  }
              },
              'parameters' => {}
          },

          'test_split' => {
              'action_class_name' => 'Armagh::CustomActions::TestSplitter',
              'input_doc_type' => 'SplitDocument',
              'output_docspecs' => {
                  'split_output' => {'type' => 'SplitOutputDocument', 'state' => 'working'}
              },
              'parameters' => {}
          },

          'test_publish' => {
              'action_class_name' => 'Armagh::CustomActions::TestPublisher',
              'doc_type' => 'PublishDocument',
              'parameters' => {}
          },

          'test_consume' => {
              'action_class_name' => 'Armagh::CustomActions::TestConsumer',
              'input_doc_type' => 'ConsumeDocument',
              'output_docspecs' => {
                  'consume_output' => {'type' => 'ConsumeOutputDocument', 'state' => 'working'}
              },
              'parameters' => {}
          }
      }

      available_actions.merge! test_actions
    end

    if specified_actions.include? 'bad_publisher'
      available_actions['bad_publisher'] = {
          'action_class_name' => 'Armagh::CustomActions::TestBadPublisher',
          'doc_type' => 'BadPublisherDocument',
          'parameters' => {}
      }
    end

    if specified_actions.include? 'bad_consumer'
      available_actions['bad_consumer'] = {
          'action_class_name' => 'Armagh::CustomActions::TestBadConsumer',
          'input_doc_type' => 'BadConsumerDocument',
          'output_docspecs' => {},
          'parameters' => {}
      }
    end

    if specified_actions.include? 'unimplemented_splitter'
      available_actions['unimplemented_splitter'] = {
          'action_class_name' => 'Armagh::CustomActions::TestUnimplementedSplitter',
          'input_doc_type' => 'UnimplementedSplitterInputDocument',
          'output_docspecs' => {
              'unimplemented_splitter_output' => {'type' => 'UnimplementedSplitterOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'too_large_collector'
      available_actions['too_large_collector'] = {
          'action_class_name' => 'Armagh::CustomActions::TestTooLargeCollector',
          'input_doc_type' => 'TooLargeInputDocType',
          'output_docspecs' => {
              'too_large_collector_output' => {'type' => 'TooLargeCollectorOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'too_large_splitter'
      available_actions['too_large_splitter'] = {
          'action_class_name' => 'Armagh::CustomActions::TestTooLargeSplitter',
          'input_doc_type' => 'TooLargeInputDocType',
          'output_docspecs' => {
              'too_large_splitter_output' => {'type' => 'TooLargeSplitterOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'edit_current_splitter'
      available_actions['edit_current_splitter'] = {
          'action_class_name' => 'Armagh::CustomActions::TestEditCurrentSplitter',
          'input_doc_type' => 'EditCurrentInputDocType',
          'output_docspecs' => {
              'edit_current_splitter_output' => {'type' => 'EditCurrentSplitterOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'update_error_splitter'
      available_actions['update_error_splitter'] = {
          'action_class_name' => 'Armagh::CustomActions::TestUpdateErrorSplitter',
          'input_doc_type' => 'UpdateErrorInputDocType',
          'output_docspecs' => {
              'update_error_splitter_output' => {'type' => 'UpdateErrorSplitterOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'notify_ops'
      available_actions['notify_ops'] = {
          'action_class_name' => 'Armagh::CustomActions::TestSplitterNotifyOps',
          'input_doc_type' => 'NotifyOpsDocType',
          'output_docspecs' => {
              'notify_ops_output' => {'type' => 'NotifyOpsDocTypeOutput', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'notify_dev'
      available_actions['notify_dev'] = {
          'action_class_name' => 'Armagh::CustomActions::TestSplitterNotifyDev',
          'input_doc_type' => 'NotifyDevDocType',
          'output_docspecs' => {
              'notify_dev_output' => {'type' => 'NotifyDevDocTypeOutput', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'change_id_publisher'
      available_actions['change_id_publisher'] = {
          'action_class_name' => 'Armagh::CustomActions::TestChangeIdPublisher',
          'doc_type' => 'PublishDocument',
          'parameters' => {}
      }
    end

    if specified_actions.include? 'full_workflow'
      full_workflow = {
          'test_collect' => {
              'action_class_name' => 'Armagh::CustomActions::TestCollector',
              'input_doc_type' => 'CollectDocument',

              'output_docspecs' => {
                  'collected_document' => {'type' => 'CollectedDocument', 'state' => 'ready'},
                  'divide_collected_document' => {'type' => 'DivideCollectedDocument', 'state' => 'ready',
                                                 'divider' => {
                                                     'divider_class_name' => 'Armagh::CustomActions::TestDivider',
                                                     'parameters' => {}
                                                 }
                  }
              },
              'parameters' => {}
          },

          'test_split_document' => {
              'action_class_name' => 'Armagh::CustomActions::TestSplitter',
              'input_doc_type' => 'DivideCollectedDocument',
              'output_docspecs' => {
                  'split_output' => {'type' => 'Document', 'state' => 'ready'}
              },
              'parameters' => {}
          },

          'test_publish' => {
              'action_class_name' => 'Armagh::CustomActions::TestPublisher',
              'doc_type' => 'Document',
              'parameters' => {}
          },

          'test_consume' => {
              'action_class_name' => 'Armagh::CustomActions::TestConsumer',
              'input_doc_type' => 'Document',
              'output_docspecs' => {
                  'consume_output' => {'type' => 'ConsumeOutputDocument', 'state' => 'ready'}
              },
              'parameters' => {}
          }
      }

      available_actions.merge! full_workflow
    end

    if specified_actions.include? 'no_such_action'
      available_actions['no_such_action'] = {
          'action_class_name' => 'Armagh::CustomActions::NoSuchAction',
          'doc_type' => 'NoActionDocument',
          'parameters' => {}
      }
    end
  end

  case config_type
    when 'launcher'
      @launcher_config = Armagh::Launcher.create_configuration(Armagh::Connection.config, '127.0.0.1_default', {'launcher' => config})
    when 'agent'
      @agent_config = Armagh::Agent.create_configuration(Armagh::Connection.config, 'default', {'agent' => config})
    else
      raise "Unknown config type #{config_type}"
  end
end