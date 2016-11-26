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
        'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
        }
      })

      Armagh::CustomActions::TestDivider.create_configuration(Armagh::Connection.config, 'test_divider', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)}
      })

      Armagh::CustomActions::TestSplitter.create_configuration(Armagh::Connection.config, 'test_split', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('SplitDocument', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('SplitOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

      Armagh::CustomActions::TestPublisher.create_configuration(Armagh::Connection.config, 'test_publish', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
      })

      Armagh::CustomActions::TestConsumer.create_configuration(Armagh::Connection.config, 'test_consume', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('ConsumeDocument', Armagh::Documents::DocState::PUBLISHED)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

    when 'bad_publisher'
      Armagh::CustomActions::TestBadPublisher.create_configuration(Armagh::Connection.config, 'bad_publisher', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublisherDocument', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublisherDocument', Armagh::Documents::DocState::PUBLISHED)}
      })

    when 'bad_consumer'
      Armagh::CustomActions::TestBadConsumer.create_configuration(Armagh::Connection.config, 'bad_consumer', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadConsumerDocument', Armagh::Documents::DocState::PUBLISHED)},
        'output' => {}
      })

    when 'unimplemented_splitter'
      Armagh::CustomActions::TestUnimplementedSplitter.create_configuration(Armagh::Connection.config, 'unimplemented_splitter', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('UnimplementedSplitterInputDocument', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('UnimplementedSplitterOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

    when 'too_large_collector'
      Armagh::CustomActions::TestTooLargeCollector.create_configuration(Armagh::Connection.config, 'too_large_collector', {
        'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
        'output' => {'output' => Armagh::Documents::DocSpec.new('TooLargeCollectorOutputDocument', Armagh::Documents::DocState::WORKING)
        }
      })

    when 'too_large_splitter'
      Armagh::CustomActions::TestTooLargeSplitter.create_configuration(Armagh::Connection.config, 'too_large_splitter', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('TooLargeInputDocType', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('TooLargeSplitterOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

    when 'edit_current_splitter'
      Armagh::CustomActions::TestEditCurrentSplitter.create_configuration(Armagh::Connection.config, 'edit_current_splitter', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('EditCurrentInputDocType', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('EditCurrentSplitterOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

    when 'update_error_splitter'
      Armagh::CustomActions::TestUpdateErrorSplitter.create_configuration(Armagh::Connection.config, 'update_error_splitter', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('UpdateErrorInputDocType', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('UpdateErrorSplitterOutputDocument', Armagh::Documents::DocState::WORKING)}
      })

    when 'notify_ops'
      Armagh::CustomActions::TestSplitterNotifyOps.create_configuration(Armagh::Connection.config, 'notify_ops', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyOpsDocType', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('NotifyOpsDocTypeOutput', Armagh::Documents::DocState::WORKING)}
      })

    when 'notify_dev'
      Armagh::CustomActions::TestSplitterNotifyDev.create_configuration(Armagh::Connection.config, 'notify_dev', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('NotifyDevDocType', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('NotifyDevDocTypeOutput', Armagh::Documents::DocState::WORKING)}
      })

    when 'change_id_publisher'
      Armagh::CustomActions::TestChangeIdPublisher.create_configuration(Armagh::Connection.config, 'change_id_publisher', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('PublishDocument', Armagh::Documents::DocState::PUBLISHED)}
      })

    when 'non_collector'
      Armagh::CustomActions::TestNonCollector.create_configuration(Armagh::Connection.config, 'non_collector', {
        'collect' => {'archive' => false, 'schedule' => '0 0 1 1 0'},
        'output' => {'collected_document' => Armagh::Documents::DocSpec.new('NonDocument', Armagh::Documents::DocState::READY)
        }
      })

    when 'archive_collector'
      Armagh::CustomActions::TestCollector.create_configuration(Armagh::Connection.config, 'archive_collector', {
        'collect' => {'archive' => true, 'schedule' => '0 0 1 1 0'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
        }
      })

    when 'full_workflow'
      Armagh::CustomActions::TestCollector.create_configuration(Armagh::Connection.config, 'test_collect', {
        'collect' => {'archive' => true, 'schedule' => '0 0 1 1 0'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('ToDivideDocument', Armagh::Documents::DocState::READY)
        }
      })

      Armagh::CustomActions::TestDivider.create_configuration(Armagh::Connection.config, 'test_divider', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('ToDivideDocument', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)}
      })

      Armagh::CustomActions::TestSplitter.create_configuration(Armagh::Connection.config, 'test_split', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('DivideCollectedDocument', Armagh::Documents::DocState::READY)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::READY)}
      })

      Armagh::CustomActions::TestPublisher.create_configuration(Armagh::Connection.config, 'test_publish', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::PUBLISHED)}
      })

      Armagh::CustomActions::TestConsumer.create_configuration(Armagh::Connection.config, 'test_consume', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('Document', Armagh::Documents::DocState::PUBLISHED)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::READY)}
      })
    when 'minute_collect'
      Armagh::CustomActions::TestCollector.create_configuration(Armagh::Connection.config, 'test_collect', {
        'collect' => {'archive' => false, 'schedule' => '* * * * *'},
        'output' => {
          'collected_document' => Armagh::Documents::DocSpec.new('CollectedDocument', Armagh::Documents::DocState::READY),
          'divide_collected_document' => Armagh::Documents::DocSpec.new('IntermediateDocument', Armagh::Documents::DocState::READY)
        }
      })

    when 'publisher_notify_good_consumer'
      Armagh::CustomActions::TestPublisherNotifyDev.create_configuration(Armagh::Connection.config, 'test_publisher_notify_dev', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublisherDocument', Armagh::Documents::DocState::READY)},
        'output' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublisherDocument', Armagh::Documents::DocState::PUBLISHED)}
      })
      Armagh::CustomActions::TestConsumer.create_configuration(Armagh::Connection.config, 'test_consume', {
        'input' => {'docspec' => Armagh::Documents::DocSpec.new('BadPublisherDocument', Armagh::Documents::DocState::PUBLISHED)},
        'output' => {'output' => Armagh::Documents::DocSpec.new('ConsumeOutputDocument', Armagh::Documents::DocState::READY)}
      })
  end
end

When(/^armagh's "([^"]*)" config is$/) do |config_type, table|
  config = table.rows_hash
  config.default = nil

  config['num_agents'] = config['num_agents'].to_i if config['num_agents']
  config['checkin_frequency'] = config['checkin_frequency'].to_i if config['checkin_frequency']
  config['timestamp'] = Time.parse(config['timestamp']) if config['timestamp']

  case config_type
    when 'launcher'
      @launcher_config = Armagh::Launcher.create_configuration(Armagh::Connection.config, '127.0.0.1_default', {'launcher' => config})
    when 'agent'
      @agent_config = Armagh::Agent.create_configuration(Armagh::Connection.config, 'default', {'agent' => config})
    else
      raise "Unknown config type #{config_type}"
  end
end