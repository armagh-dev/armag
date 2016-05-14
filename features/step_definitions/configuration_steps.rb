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
require_relative '../../lib/action/action_manager'

require 'test/unit/assertions'

require 'log4r'
require 'time'


When(/^armagh's "([^"]*)" config is$/) do |config_type, table|
  config = table.rows_hash

  config['num_agents'] = config['num_agents'].to_i if config['num_agents']
  config['checkin_frequency'] = config['checkin_frequency'].to_i if config['checkin_frequency']
  config['timestamp'] = Time.parse(config['timestamp']) if config['timestamp']

  if config['available_actions']
    specified_actions = config['available_actions'].split(/\s*,\s*/)
    available_actions = {}

    if specified_actions.include? 'test_actions'
      test_actions = {
          'test_collect' => {
              'action_class_name' => 'Armagh::CustomActions::TestCollector',
              'input_doc_type' => 'CollectDocument',

              'output_docspecs' => {
                  'collected_document' => {'type' => 'CollectedDocument', 'state' => 'ready'},
                  'split_collected_document' => {'type' => 'SplitCollectedDocument', 'state' => 'ready',
                                                 'splitter' => {
                                                     'splitter_class_name' => 'Armagh::CustomActions::TestSplitter',
                                                     'parameters' => {}
                                                 }
                  }
              },
              'parameters' => {}
          },

          'test_parse' => {
              'action_class_name' => 'Armagh::CustomActions::TestParser',
              'input_doc_type' => 'ParseDocument',
              'output_docspecs' => {
                  'parse_output' => {'type' => 'ParseOutputDocument', 'state' => 'working'}
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

    if specified_actions.include? 'unimplemented_parser'
      available_actions['unimplemented_parser'] = {
          'action_class_name' => 'Armagh::CustomActions::TestUnimplementedParser',
          'input_doc_type' => 'UnimplementedParserInputDocument',
          'output_docspecs' => {
              'unimplemented_parser_output' => {'type' => 'UnimplementedParserOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'duplicate_collector'
      available_actions['duplicate_collector'] = {
          'action_class_name' => 'Armagh::CustomActions::TestDuplicateCollector',
          'input_doc_type' => 'DuplicateInputDocType',
          'output_docspecs' => {
              'duplicate_collector_output' => {'type' => 'DuplicateCollectorOutputDocument', 'state' => 'working'}
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

    if specified_actions.include? 'too_large_parser'
      available_actions['too_large_parser'] = {
          'action_class_name' => 'Armagh::CustomActions::TestTooLargeParser',
          'input_doc_type' => 'TooLargeInputDocType',
          'output_docspecs' => {
              'too_large_parser_output' => {'type' => 'TooLargeParserOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'edit_current_parser'
      available_actions['edit_current_parser'] = {
          'action_class_name' => 'Armagh::CustomActions::TestEditCurrentParser',
          'input_doc_type' => 'EditCurrentInputDocType',
          'output_docspecs' => {
              'edit_current_parser_output' => {'type' => 'EditCurrentParserOutputDocument', 'state' => 'working'}
          },
          'parameters' => {}
      }
    end

    if specified_actions.include? 'update_error_parser'
      available_actions['update_error_parser'] = {
          'action_class_name' => 'Armagh::CustomActions::TestUpdateErrorParser',
          'input_doc_type' => 'UpdateErrorInputDocType',
          'output_docspecs' => {
              'update_error_parser_output' => {'type' => 'UpdateErrorParserOutputDocument', 'state' => 'working'}
          },
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
                  'split_collected_document' => {'type' => 'SplitCollectedDocument', 'state' => 'ready',
                                                 'splitter' => {
                                                     'splitter_class_name' => 'Armagh::CustomActions::TestSplitter',
                                                     'parameters' => {}
                                                 }
                  }
              },
              'parameters' => {}
          },

          'test_parse_document' => {
              'action_class_name' => 'Armagh::CustomActions::TestParser',
              'input_doc_type' => 'SplitCollectedDocument',
              'output_docspecs' => {
                  'parse_output' => {'type' => 'Document', 'state' => 'ready'}
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


    @action_manager ||= Armagh::ActionManager.new(nil, Log4r::Logger.root)
    @action_manager.set_available_actions(available_actions)

    config['available_actions'] = available_actions
  end

  MongoSupport.instance.set_config(config_type, config)
end