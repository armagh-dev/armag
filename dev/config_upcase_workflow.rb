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

available_actions = {
    'collect' => {
        'input_doctype' => 'CollectDoc',
        'output_doctype' => 'CollectedDoc',
        'action_class_name' => 'NoraghActions::FileCollectionAction',
        'config' => {
            'delete' => false,
            'path' => '/tmp/collection',
            'count' => 10
        }
    },

    'upcase' => {
        'input_doctype' => 'CollectedDoc',
        'output_doctype' => 'UpcaseDoc',
        'action_class_name' => 'NoraghActions::UpcaseAction',
        'config' => {}
    }
}

config = {
    'num_agents' => 1,
    'checkin_frequency' => 60,
    'timestamp' => Time.now,
    'available_actions' => available_actions
}

Connection.config.find('type' => 'launcher').replace_one(config.merge({'type' => 'launcher'}), {upsert: true})