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

@action @agent
Feature: Actions Execution
  I want actions to be executed on documents

  Scenario: Have nothing to work on
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 4 |
      | checkin_frequency | 1 |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
      | idle |
      | idle |
      | idle |

  Scenario: Have a document for a collector
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "CollectDocument" with a "ready" state, id "123", and content "'doesnt matter'"
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And  I should see a "CollectedDocument" with the following
      | _id               | '123_collected'     |
      | pending_actions   | []                  |
      | failed_actions    | {}                  |
      | draft_content     | 'collected content' |
      | published_content | {}                  |
      | state             | 'ready'             |
      | locked            | false               |
      | failure           | false               |
      | pending_work      | false               |
    And  I should see a "SplitCollectedDocument" with the following
      | _id               | '123_collected_post_split' |
      | pending_actions   | []                         |
      | failed_actions    | {}                         |
      | draft_content     | 'content-for-splitting'    |
      | published_content | {}                         |
      | state             | 'ready'                    |
      | locked            | false                      |
      | failure           | false                      |
      | pending_work      | false                      |
    And the logs should contain "Test Collect Running"
    And the logs should contain "Test Collect Splitter Running"
    And the logs should not contain "ERROR"

  Scenario: Have a document for a parser
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "ParseDocument" with a "ready" state, id "123", and content "'doesnt matter'"
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And  I should see a "ParseOutputDocument" with the following
      | _id               | 'parse_1'                                                    |
      | meta              | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | pending_actions   | []                                                           |
      | failed_actions    | {}                                                           |
      | draft_content     | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | published_content | {}                                                           |
      | state             | 'working'                                                    |
      | locked            | false                                                        |
      | failure           | false                                                        |
      | pending_work      | false                                                        |
    And  I should see a "ParseOutputDocument" with the following
      | _id               | 'parse_2'                                         |
      | meta              | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | pending_actions   | []                                                |
      | failed_actions    | {}                                                |
      | draft_content     | {'text_2' => 'text_content_2'}                    |
      | published_content | {}                                                |
      | state             | 'working'                                         |
      | locked            | false                                             |
      | failure           | false                                             |
      | pending_work      | false                                             |
    And I should see 0 "ParseDocument" documents
    And the logs should contain "Test Parse Running"
    And the logs should not contain "ERROR"

  Scenario: Have a document for a publisher
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, id "123", and content "{'content' => 'some content'}"
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And  I should see a "PublishDocument" with the following
      | _id               | '123'                         |
      | pending_actions   | []                            |
      | failed_actions    | {}                            |
      | draft_content     | {}                            |
      | published_content | {'content' => 'some content'} |
      | state             | 'published'                   |
      | locked            | false                         |
      | failure           | false                         |
      | pending_work      | false                         |
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"

  Scenario: Have a document for a consumer
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "ConsumeDocument" with a "ready" state, id "123", and content "'incoming content'"
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And  I should see a "ConsumeOutputDocument" with the following
      | _id               | 'consume_1'                                                |
      | meta              | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | pending_actions   | []                                                           |
      | failed_actions    | {}                                                           |
      | draft_content     | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | published_content | {}                                                           |
      | state             | 'working'                                                    |
      | locked            | false                                                        |
      | failure           | false                                                        |
      | pending_work      | false                                                        |
    And  I should see a "ConsumeOutputDocument" with the following
      | _id               | 'consume_2'                                     |
      | meta              | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | pending_actions   | []                                                |
      | failed_actions    | {}                                                |
      | draft_content     | {'text_2' => 'text_content_2'}                    |
      | published_content | {}                                                |
      | state             | 'working'                                         |
      | locked            | false                                             |
      | failure           | false                                             |
      | pending_work      | false                                             |
    And I should see a "ConsumeDocument" with the following
      | _id           | '123'              |
      | draft_content | 'incoming content' |
      | state         | 'ready'            |
    And the logs should contain "Test Consume Running"
    And the logs should not contain "ERROR"

  Scenario: Have a document with an action that doesn't implement the required action method
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | unimplemented_parser |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "UnimplementedParserInputDocument" with a "ready" state, id "123", and content "'incoming content'"
    And I wait 5 seconds
    Then I should see a "UnimplementedParserInputDocument" with the following
      | _id               | '123'                                                                                                                                                                            |
      | meta              | {}                                                                                                                                                                               |
      | pending_actions   | []                                                                                                                                                                               |
      | failed_actions    | {'unimplemented_parser' => {'class' => 'Armagh::ActionErrors::ActionMethodNotImplemented', 'message' => 'ParseActions must overwrite the parse method.', 'trace' => 'anything'}} |
      | draft_content     | 'incoming content'                                                                                                                                                               |
      | published_content | {}                                                                                                                                                                               |
      | state             | 'ready'                                                                                                                                                                          |
      | locked            | false                                                                                                                                                                            |
      | failure           | true                                                                                                                                                                             |
      | pending_work      | false                                                                                                                                                                            |
    And the logs should contain "ERROR"

  Scenario: Have a document to work on with an action that fails in the middle
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | bad_publisher |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "BadPublisherDocument" with a "ready" state, id "123", and content "'incoming content'"
    And I wait 5 seconds
    Then I should see a "BadPublisherDocument" with the following
      | _id               | '123'                                                                                                      |
      | meta              | {}                                                                                                         |
      | pending_actions   | []                                                                                                         |
      | failed_actions    | {'bad_publisher' => {'class' => 'RuntimeError', 'message' => 'poorly implemented', 'trace' => 'anything'}} |
      | draft_content     | 'incoming content'                                                                                         |
      | published_content | {}                                                                                                         |
      | state             | 'ready'                                                                                                    |
      | locked            | false                                                                                                      |
      | failure           | true                                                                                                       |
      | pending_work      | false                                                                                                      |
    And the logs should contain "ERROR"

  Scenario: Complete Document Workflow
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 2 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | full_workflow |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
      | idle |
    When I insert 1 "CollectDocument" with a "ready" state, id "123", and content "'doesnt matter'"
    And I wait 30 seconds
    Then the logs should contain "Test Collect Running"
    And the logs should contain "Test Collect Splitter Running"
    And the logs should contain "Test Consume Running"
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"
    And  I should see a "ConsumeOutputDocument" with the following
      | _id          | 'consume_1' |
      | state        | 'ready'       |
      | locked       | false         |
      | failure      | false         |
      | pending_work | false         |
    And  I should see a "ConsumeOutputDocument" with the following
      | _id          | 'consume_2' |
      | state        | 'ready'       |
      | locked       | false         |
      | failure      | false         |
      | pending_work | false         |
    And  I should see a "Document" with the following
      | _id          | 'parse_1'   |
      | state        | 'published' |
      | locked       | false       |
      | failure      | false       |
      | pending_work | false       |
    And  I should see a "Document" with the following
      | _id          | 'parse_2'   |
      | state        | 'published' |
      | locked       | false       |
      | failure      | false       |
      | pending_work | false       |
    And  I should see a "CollectedDocument" with the following
      | _id          | '123_collected' |
      | state        | 'ready'         |
      | locked       | false           |
      | failure      | false           |
      | pending_work | false           |