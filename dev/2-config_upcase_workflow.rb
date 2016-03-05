#!/usr/bin/env ruby
#
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

require_relative '../lib/connection'

include Armagh

launcher_config = {
    'num_agents' => 1,
    'checkin_frequency' => 60,
    'timestamp' => Time.now,
    'log_level' => 'debug'
}

agent_config = {
    'timestamp' => Time.now,
    'log_level' => 'debug',
    'available_actions' => {
        'read' => {
            'action_class_name' => 'Armagh::CustomActions::FileReadAction',
            'input_docspecs' => {
                'ready_to_collect' => {'type' => 'CollectDoc', 'state' => 'ready'},
            },
            'output_docspecs' => {
                'collected' => {'type' => 'TestDocument', 'state' => 'ready',
                                'splitter' => {
                                    'splitter_class_name' => 'Armagh::CustomActions::FileSplitter',
                                    'parameters' => {
                                        'lines_per_split' => 2
                                    }
                                }
                },
                'empty' => {'type' => 'EmptyDocument', 'state' => 'ready'}, # Not doing anything with empty documents yet.
            },
            'parameters' => {
                'delete' => false,
                'path' => '/tmp/input',
                'count' => 10
            }
        },

        'upcase' => {
            'action_class_name' => 'Armagh::CustomActions::UpcaseAction',
            'doctype' => 'TestDocument',
            'parameters' => {}
        },

        'write' => {
            'action_class_name' => 'Armagh::CustomActions::FileWriteAction',
            'input_docspecs' => {
                'doc_to_write' => {'type' => 'TestDocument', 'state' => 'published'},
            },
            'output_docspecs' => {},
            'parameters' => {
                'path' => '/tmp/output'
            }
        }
    }
}

Connection.config.find('type' => 'launcher').replace_one(launcher_config.merge({'type' => 'launcher'}), {upsert: true})
Connection.config.find('type' => 'agent').replace_one(agent_config.merge({'type' => 'agent'}), {upsert: true})
