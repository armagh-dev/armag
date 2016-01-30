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

require_relative '../support/mongo_support'

require 'test/unit/assertions'
require 'logger'
require 'time'


When(/^armagh's "([^"]*)" config is$/) do |config_type, table|
  config = table.rows_hash

  config['num_agents'] = config['num_agents'].to_i if config['num_agents']
  config['checkin_frequency'] = config['checkin_frequency'].to_i if config['checkin_frequency']
  config['timestamp'] = Time.parse(config['timestamp']) if config['timestamp']

  if config['available_actions']
    specified_actions = config['available_actions'].split(/\s*,\s*/)
    available_actions = {}

    if specified_actions.include? 'sleep_action'
      available_actions['sleep_action'] = {
          'input_doctype' => 'TestDocumentInput',
          'output_doctype' => 'TestDocumentOutput',
          'action_class_name' => 'ClientActions::SleepAction',
          'config' => {'seconds' => 2}
      }
    end

    if specified_actions.include? 'sleep_action_default'
      available_actions['sleep_action_default'] = {
          'input_doctype' => Armagh::ClientActions::SleepAction.default_input_doctype,
          'output_doctype' => Armagh::ClientActions::SleepAction.default_output_doctype,
          'action_class_name' => 'ClientActions::SleepAction',
          'config' => {'seconds' => Armagh::ClientActions::SleepAction.defined_parameters['seconds']['default']}
      }
    end

    if specified_actions.include? 'non_existent_action'
      available_actions['non_existent_action'] = {
          'input_doctype' => 'TestDocumentInput',
          'output_doctype' => 'TestDocumentOutput',
          'action_class_name' => 'NotARealClass'
      }
    end

    if specified_actions.include? 'no_execution_action'
      available_actions['no_execution_action'] = {
          'input_doctype' => 'TestDocumentInput',
          'output_doctype' => 'TestDocumentOutput',
          'action_class_name' => 'ClientActions::NoExecutionAction'
      }
    end

    if specified_actions.include? 'middle_fail_action'
      available_actions['middle_fail_action'] = {
          'input_doctype' => 'TestDocumentInput',
          'output_doctype' => 'TestDocumentOutput',
          'action_class_name' => 'ClientActions::MiddleFailAction'
      }
    end

    if specified_actions.include? 'external_document_action'
      available_actions['external_document_action'] = {
          'input_doctype' => 'TestDocumentInput',
          'output_doctype' => 'ExternalDocument',
          'action_class_name' => 'ClientActions::ExternalDocumentAction'
      }
    end

    config['available_actions'] = available_actions
  end

  MongoSupport.instance.set_config(config_type, config)
end