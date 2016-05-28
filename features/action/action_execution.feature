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
    And I wait 3 seconds
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "CollectDocument" with a "ready" state, id "123_trigger", content "{'doesnt_matter' => true}", metadata "{}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "CollectedDocument" in "documents" with the following
      | _id               | '123_collected'     |
      | pending_actions   | []                  |
      | failed_actions    | {}                  |
      | draft_content     | 'collected content' |
      | published_content | {}                  |
      | state             | 'ready'             |
      | locked            | false               |
      | failure           | nil                 |
      | pending_work      | nil                 |
      | version           | APP_VERSION         |
    And I should see a "SplitCollectedDocument" in "documents" with the following
      | _id               | '123_collected_post_split' |
      | pending_actions   | []                         |
      | failed_actions    | {}                         |
      | draft_content     | 'content-for-splitting'    |
      | published_content | {}                         |
      | state             | 'ready'                    |
      | locked            | false                      |
      | failure           | nil                        |
      | pending_work      | nil                        |
      | version           | APP_VERSION                |
    And I should see 0 "CollectDocument" documents in the "documents" collection
    And I should see a "CollectDocument" in "archive" with the following
      | _id                | '123_trigger'             |
      | draft_metadata     | {'docs_collected' => 2}   |
      | published_metadata | {}                        |
      | pending_actions    | []                        |
      | failed_actions     | {}                        |
      | draft_content      | {'doesnt_matter' => true} |
      | published_content  | {}                        |
      | state              | 'ready'                   |
      | locked             | false                     |
      | failure            | nil                       |
      | pending_work       | nil                       |
      | version            | APP_VERSION               |
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "ParseDocument" with a "ready" state, id "123", content "{'doesnt_matter' => true}", metadata "{'doesnt_matter' => true}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "ParseOutputDocument" in "documents" with the following
      | _id                | 'parse_1'                                                    |
      | draft_metadata     | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | published_metadata | {}                                                           |
      | pending_actions    | []                                                           |
      | failed_actions     | {}                                                           |
      | draft_content      | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | published_content  | {}                                                           |
      | state              | 'working'                                                    |
      | locked             | false                                                        |
      | failure            | nil                                                          |
      | pending_work       | nil                                                          |
      | version            | APP_VERSION                                                  |
    And  I should see a "ParseOutputDocument" in "documents" with the following
      | _id                | 'parse_2'                                         |
      | draft_metadata     | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | published_metadata | {}                                                |
      | pending_actions    | []                                                |
      | failed_actions     | {}                                                |
      | draft_content      | {'text_2' => 'text_content_2'}                    |
      | published_content  | {}                                                |
      | state              | 'working'                                         |
      | locked             | false                                             |
      | failure            | nil                                               |
      | pending_work       | nil                                               |
      | version            | APP_VERSION                                       |
    And I should see 0 "ParseDocument" documents in the "documents" collection
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, id "123", content "{'content' => 'some content'}", metadata "{'meta' => 'some meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | _id                | '123'                         |
      | pending_actions    | []                            |
      | failed_actions     | {}                            |
      | draft_metadata     | {}                            |
      | published_metadata | {'meta' => 'some meta'}       |
      | draft_content      | {}                            |
      | published_content  | {'content' => 'some content'} |
      | state              | 'published'                   |
      | locked             | false                         |
      | failure            | nil                           |
      | pending_work       | nil                           |
      | version            | APP_VERSION                   |
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"
    And I should see 0 "PublishDocument" documents in the "documents" collection

  Scenario: Have a document for a publisher that updates a previously published document
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I run armagh
    And I wait 3 seconds
    And I insert 1 "PublishDocument" with a "published" state, id "123", published content "{'orig_content' => 'old published content'}", published metadata "{'orig_meta' => 'old published metadata'}"
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, id "123", content "{'new_content' => 'new content'}", metadata "{'new_meta' => 'new metadata'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | _id                | '123'                                                                       |
      | pending_actions    | []                                                                          |
      | failed_actions     | {}                                                                          |
      | draft_metadata     | {}                                                                          |
      | published_metadata | {'orig_meta' => 'old published metadata', 'new_meta' => 'new metadata'}     |
      | draft_content      | {}                                                                          |
      | published_content  | {'orig_content' => 'old published content', 'new_content' => 'new content'} |
      | state              | 'published'                                                                 |
      | locked             | false                                                                       |
      | failure            | nil                                                                         |
      | pending_work       | nil                                                                         |
      | version            | APP_VERSION                                                                 |
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"
    And I should see 0 "PublishDocument" documents in the "documents" collection

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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "ConsumeDocument" with a "published" state, id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "ConsumeOutputDocument" in "documents" with the following
      | _id                | 'consume_1'                                                  |
      | draft_metadata     | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | published_metadata | {}                                                           |
      | pending_actions    | []                                                           |
      | failed_actions     | {}                                                           |
      | draft_content      | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | published_content  | {}                                                           |
      | state              | 'working'                                                    |
      | locked             | false                                                        |
      | failure            | nil                                                          |
      | pending_work       | nil                                                          |
      | version            | APP_VERSION                                                  |
    And  I should see a "ConsumeOutputDocument" in "documents" with the following
      | _id                | 'consume_2'                                       |
      | draft_metadata     | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | published_metadata | {}                                                |
      | pending_actions    | []                                                |
      | failed_actions     | {}                                                |
      | draft_content      | {'text_2' => 'text_content_2'}                    |
      | published_content  | {}                                                |
      | state              | 'working'                                         |
      | locked             | false                                             |
      | failure            | nil                                               |
      | pending_work       | nil                                               |
      | version            | APP_VERSION                                       |
    And I should see a "ConsumeDocument" in "documents.ConsumeDocument" with the following
      | _id                | '123'                          |
      | draft_content      | {'text' => 'incoming content'} |
      | published_content  | {}                             |
      | draft_metadata     | {'meta' => 'incoming meta'}    |
      | published_metadata | {}                             |
      | state              | 'published'                    |
      | version            | APP_VERSION                    |
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "UnimplementedParserInputDocument" with a "ready" state, id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "UnimplementedParserInputDocument" documents in the "documents" collection
    Then I should see a "UnimplementedParserInputDocument" in "failures" with the following
      | _id                | '123'                                                                                                                                                                            |
      | draft_metadata     | {'meta' => 'incoming meta'}                                                                                                                                                      |
      | published_metadata | {}                                                                                                                                                                               |
      | pending_actions    | []                                                                                                                                                                               |
      | failed_actions     | {'unimplemented_parser' => {'class' => 'Armagh::ActionErrors::ActionMethodNotImplemented', 'message' => 'ParseActions must overwrite the parse method.', 'trace' => 'anything'}} |
      | draft_content      | {'text' => 'incoming content'}                                                                                                                                                   |
      | published_content  | {}                                                                                                                                                                               |
      | state              | 'ready'                                                                                                                                                                          |
      | locked             | false                                                                                                                                                                            |
      | failure            | true                                                                                                                                                                             |
      | pending_work       | nil                                                                                                                                                                              |
      | version            | APP_VERSION                                                                                                                                                                      |
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "BadPublisherDocument" with a "ready" state, id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "BadPublisherDocument" documents in the "documents" collection
    Then I should see a "BadPublisherDocument" in "failures" with the following
      | _id                | '123'                                                                                                      |
      | draft_metadata     | {'meta' => 'incoming meta'}                                                                                |
      | published_metadata | {}                                                                                                         |
      | pending_actions    | []                                                                                                         |
      | failed_actions     | {'bad_publisher' => {'class' => 'RuntimeError', 'message' => 'poorly implemented', 'trace' => 'anything'}} |
      | draft_content      | {'text' => 'incoming content'}                                                                             |
      | published_content  | {}                                                                                                         |
      | state              | 'ready'                                                                                                    |
      | locked             | false                                                                                                      |
      | failure            | true                                                                                                       |
      | pending_work       | nil                                                                                                        |
      | version            | APP_VERSION                                                                                                |
    And the logs should contain "ERROR"

  Scenario: Have a publisher to work on with an action that fails in the middle that remains published
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | bad_consumer |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "BadConsumerDocument" with a "published" state, id "123", published content "{'content' => 'published content'}", published metadata "{'meta' => 'published metadata'}"
    And I wait 7 seconds
    Then I should see 0 "BadConsumerDocument" documents in the "failures" collection
    Then I should see a "BadConsumerDocument" in "documents.BadConsumerDocument" with the following
      | _id                | '123'                                                                                                     |
      | draft_metadata     | {}                                                                                                        |
      | published_metadata | {'meta' => 'published metadata'}                                                                          |
      | pending_actions    | []                                                                                                        |
      | failed_actions     | {'bad_consumer' => {'class' => 'RuntimeError', 'message' => 'poorly implemented', 'trace' => 'anything'}} |
      | draft_content      | {}                                                                                                        |
      | published_content  | {'content' => 'published content'}                                                                        |
      | state              | 'published'                                                                                               |
      | locked             | false                                                                                                     |
      | failure            | true                                                                                                      |
      | pending_work       | nil                                                                                                       |
      | version            | APP_VERSION                                                                                               |
    And the logs should contain "ERROR"

  Scenario: Have a collector that produces duplicate documents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | duplicate_collector |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "DuplicateInputDocType" with a "ready" state, id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 1 "DuplicateCollectorOutputDocument" documents in the "documents" collection
    Then I should see a "DuplicateInputDocType" in "failures" with the following
      | _id                | 'incoming'                                                                                                                                                                                                          |
      | draft_metadata     | {'meta' => 'incoming meta'}                                                                                                                                                                                         |
      | published_metadata | {}                                                                                                                                                                                                                  |
      | pending_actions    | []                                                                                                                                                                                                                  |
      | failed_actions     | {'duplicate_collector' => {'class' => 'Armagh::ActionErrors::DocumentUniquenessError', 'message' => 'Unable to create document 123.  This document already exists.', 'trace' => 'anything', 'cause' => 'anything'}} |
      | draft_content      | {'text' => 'incoming content'}                                                                                                                                                                                      |
      | published_content  | {}                                                                                                                                                                                                                  |
      | state              | 'ready'                                                                                                                                                                                                             |
      | locked             | false                                                                                                                                                                                                               |
      | failure            | true                                                                                                                                                                                                                |
      | pending_work       | nil                                                                                                                                                                                                                 |
      | version            | APP_VERSION                                                                                                                                                                                                         |
    And the logs should contain "ERROR"

  Scenario: Have a collector that produces documents that are too large
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | too_large_collector |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "TooLargeInputDocType" with a "ready" state, id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "TooLargeCollectorOutputDocument" documents in the "documents" collection
    Then I should see a "TooLargeInputDocType" in "failures" with the following
      | _id               | 'incoming'                                                                                                                                                                                                                             |
      | draft_metadata    | {'meta' => 'incoming meta'}                                                                                                                                                                                                            |
      | pending_actions   | []                                                                                                                                                                                                                                     |
      | failed_actions    | {'too_large_collector' => {'class' => 'Armagh::ActionErrors::DocumentSizeError', 'message' => 'Document 123 is too large.  Consider using a splitter or parser to split the document.', 'trace' => 'anything', 'cause' => 'anything'}} |
      | draft_content     | {'text' => 'incoming content'}                                                                                                                                                                                                         |
      | published_content | {}                                                                                                                                                                                                                                     |
      | state             | 'ready'                                                                                                                                                                                                                                |
      | locked            | false                                                                                                                                                                                                                                  |
      | failure           | true                                                                                                                                                                                                                                   |
      | pending_work      | nil                                                                                                                                                                                                                                    |
      | version           | APP_VERSION                                                                                                                                                                                                                            |
    And the logs should contain "ERROR"

  Scenario: Have a parser that edits documents that are too large
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | too_large_parser |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "TooLargeInputDocType" with a "ready" state, id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "TooLargeParserOutputDocument" documents in the "documents" collection
    Then I should see a "TooLargeInputDocType" in "failures" with the following
      | _id               | 'incoming'                                                                                                                                                                                                                                |
      | draft_metadata    | {'meta' => 'incoming meta'}                                                                                                                                                                                                               |
      | pending_actions   | []                                                                                                                                                                                                                                        |
      | failed_actions    | {'too_large_parser' => {'class' => 'Armagh::ActionErrors::DocumentSizeError', 'message' => 'Document parse_123 is too large.  Consider using a splitter or parser to split the document.', 'trace' => 'anything', 'cause' => 'anything'}} |
      | draft_content     | {'text' => 'incoming content'}                                                                                                                                                                                                            |
      | published_content | {}                                                                                                                                                                                                                                        |
      | state             | 'ready'                                                                                                                                                                                                                                   |
      | locked            | false                                                                                                                                                                                                                                     |
      | failure           | true                                                                                                                                                                                                                                      |
      | pending_work      | nil                                                                                                                                                                                                                                       |
      | version           | APP_VERSION                                                                                                                                                                                                                               |
    And the logs should contain "ERROR"

  Scenario: Have a parser that edits the current document
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | edit_current_parser |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "EditCurrentInputDocType" with a "ready" state, id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "EditCurrentParserOutputDocument" documents in the "documents" collection
    Then I should see a "EditCurrentInputDocType" in "failures" with the following
      | _id                | 'incoming'                                                                                                                                                                                                        |
      | draft_metadata     | {'meta' => 'incoming meta'}                                                                                                                                                                                       |
      | published_metadata | {}                                                                                                                                                                                                                |
      | pending_actions    | []                                                                                                                                                                                                                |
      | failed_actions     | {'edit_current_parser' => {'class' => 'Armagh::ActionErrors::DocumentError', 'message' => 'Cannot edit document \'incoming\'.  It is the same document that was passed into the action.', 'trace' => 'anything'}} |
      | draft_content      | {'text' => 'incoming content'}                                                                                                                                                                                    |
      | published_content  | {}                                                                                                                                                                                                                |
      | state              | 'ready'                                                                                                                                                                                                           |
      | locked             | false                                                                                                                                                                                                             |
      | failure            | true                                                                                                                                                                                                              |
      | pending_work       | nil                                                                                                                                                                                                               |
      | version            | APP_VERSION                                                                                                                                                                                                       |
    And the logs should contain "ERROR"

  Scenario: Have a parser that has an error during document update
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | update_error_parser |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "UpdateErrorParserOutputDocument" with a "working" state, id "update_id", content "{'existing_content'=>'some content'}", metadata "{'existing_metadata'=>'some meta'}"
    And I insert 1 "UpdateErrorInputDocType" with a "ready" state, id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 1 "UpdateErrorParserOutputDocument" documents in the "documents" collection
    And I should see a "UpdateErrorInputDocType" in "failures" with the following
      | _id                | 'incoming'                                                                                            |
      | draft_metadata     | {'meta' => 'incoming meta'}                                                                           |
      | published_metadata | {}                                                                                                    |
      | pending_actions    | []                                                                                                    |
      | failed_actions     | {'update_error_parser' => {'class' => 'RuntimeError', 'message' => 'Failure', 'trace' => 'anything'}} |
      | draft_content      | {'text' => 'incoming content'}                                                                        |
      | published_content  | {}                                                                                                    |
      | state              | 'ready'                                                                                               |
      | locked             | false                                                                                                 |
      | failure            | true                                                                                                  |
      | pending_work       | nil                                                                                                   |
      | version            | APP_VERSION                                                                                           |
    And I should see a "UpdateErrorParserOutputDocument" in "documents" with the following
      | _id                | 'update_id'                            |
      | draft_metadata     | {'existing_metadata'=>'some meta'}     |
      | published_metadata | {}                                     |
      | pending_actions    | []                                     |
      | failed_actions     | {}                                     |
      | draft_content      | {'existing_content' => 'some content'} |
      | published_content  | {}                                     |
      | state              | 'working'                              |
      | locked             | false                                  |
      | failure            | nil                                    |
      | pending_work       | nil                                    |
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
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
      | idle |
    When I insert 1 "CollectDocument" with a "ready" state, id "123_trigger", content "{'doesnt_matter' => true}", metadata "{}"
    And I wait 30 seconds
    Then the logs should contain "Test Collect Running"
    And the logs should contain "Test Collect Splitter Running"
    And the logs should contain "Test Consume Running"
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"
    And I should see a "ConsumeOutputDocument" in "documents" with the following
      | _id          | 'consume_1' |
      | state        | 'ready'     |
      | locked       | false       |
      | failure      | nil         |
      | pending_work | nil         |
      | version      | APP_VERSION |
    And I should see a "ConsumeOutputDocument" in "documents" with the following
      | _id          | 'consume_2' |
      | state        | 'ready'     |
      | locked       | false       |
      | failure      | nil         |
      | pending_work | nil         |
      | version      | APP_VERSION |
    And I should see a "Document" in "documents.Document" with the following
      | _id          | 'parse_1'   |
      | state        | 'published' |
      | locked       | false       |
      | failure      | nil         |
      | pending_work | nil         |
      | version      | APP_VERSION |
    And I should see a "Document" in "documents.Document" with the following
      | _id          | 'parse_2'   |
      | state        | 'published' |
      | locked       | false       |
      | failure      | nil         |
      | pending_work | nil         |
      | version      | APP_VERSION |
    And I should see a "CollectedDocument" in "documents" with the following
      | _id          | '123_collected' |
      | state        | 'ready'         |
      | locked       | false           |
      | failure      | nil             |
      | pending_work | nil             |
      | version      | APP_VERSION     |
    And I should see a "CollectDocument" in "archive" with the following
      | _id                | '123_trigger'             |
      | draft_metadata     | {'docs_collected' => 2}   |
      | published_metadata | {}                        |
      | pending_actions    | []                        |
      | failed_actions     | {}                        |
      | draft_content      | {'doesnt_matter' => true} |
      | published_content  | {}                        |
      | state              | 'ready'                   |
      | locked             | false                     |
      | failure            | nil                       |
      | pending_work       | nil                       |
      | version            | APP_VERSION               |
    And I should see 0 "CollectDocument" documents in the "document" collection

  Scenario: Republishing a document with a newer armagh version updates the version in the document
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | test_actions |
    And I insert 1 "PublishDocument" with a "published" state, id "123", published content "{'orig_content' => 'old published content'}", published metadata "{'orig_meta' => 'old published metadata'}"
    And I set all "documents.PublishDocument" documents to have the following
      | version | 'old_version' |
    Then  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | _id     | '123'         |
      | version | 'old_version' |
    When I insert 1 "PublishDocument" with a "ready" state, id "123", content "{'new_content' => 'new content'}", metadata "{'new_meta' => 'new meta'}"
    And I run armagh
    And I wait 3 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | _id     | '123'       |
      | version | APP_VERSION |
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"