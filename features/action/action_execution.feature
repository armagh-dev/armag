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
      | num_agents        | 1     |
      | checkin_frequency | 1     |
      | log_level         | debug |
    And armagh's "agent" config is
      | log_level         | debug        |
    And armagh's workflow config is "test_actions"
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "__COLLECT__test_collect" with a "ready" state, document_id "123_trigger", content "{'doesnt_matter' => true}", metadata "{}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "CollectedDocument" in "documents" with the following
      | document_id         | '[UUID]'                                                 |
      | pending_actions     | []                                                       |
      | dev_errors          | {}                                                       |
      | ops_errors          | {}                                                       |
      | content             | {'bson_binary' => BSON::Binary.new('collected content')} |
      | state               | 'ready'                                                  |
      | locked              | false                                                    |
      | error               | nil                                                      |
      | pending_work        | nil                                                      |
      | version             | APP_VERSION                                              |
      | source              | {'type' => 'url', 'url' => 'from test'}                  |
      | collection_task_ids | not_empty                                                |
    And I should see a "DivideCollectedDocument" in "documents" with the following
      | document_id         | '[UUID]'                                                    |
      | pending_actions     | []                                                          |
      | dev_errors          | {}                                                          |
      | ops_errors          | {}                                                          |
      | content             | {'bson_binary' => BSON::Binary.new('content-for-dividing')} |
      | state               | 'ready'                                                     |
      | locked              | false                                                       |
      | error               | nil                                                         |
      | pending_work        | nil                                                         |
      | version             | APP_VERSION                                                 |
      | source              | {'type' => 'url', 'url' => 'from test'}                     |
      | collection_task_ids | not_empty                                                   |
    And I should see 0 "CollectDocument" documents in the "documents" collection
    And I should see a "CollectDocument" in "archive" with the following
      | document_id     | '123_trigger'             |
      | metadata        | {'docs_collected' => 2}   |
      | pending_actions | []                        |
      | dev_errors      | {}                        |
      | ops_errors      | {}                        |
      | content         | {'doesnt_matter' => true} |
      | state           | 'ready'                   |
      | locked          | false                     |
      | error           | nil                       |
      | pending_work    | nil                       |
      | version         | APP_VERSION               |
    And the logs should contain "Test Collect Running"
    And the logs should contain "Test Divider Running"
    And the logs should not contain "ERROR"

  Scenario: Have a document for a splitter
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
    When I insert 1 "SplitDocument" with a "ready" state, document_id "123", content "{'doesnt_matter' => true}", metadata "{'doesnt_matter' => true}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "SplitOutputDocument" in "documents" with the following
      | document_id     | 'split_1'                                                    |
      | metadata        | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | pending_actions | []                                                           |
      | dev_errors      | {}                                                           |
      | ops_errors      | {}                                                           |
      | content         | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | state           | 'working'                                                    |
      | locked          | false                                                        |
      | error           | nil                                                          |
      | pending_work    | nil                                                          |
      | version         | APP_VERSION                                                  |
    And  I should see a "SplitOutputDocument" in "documents" with the following
      | document_id     | 'split_2'                                         |
      | metadata        | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | pending_actions | []                                                |
      | dev_errors      | {}                                                |
      | ops_errors      | {}                                                |
      | content         | {'text_2' => 'text_content_2'}                    |
      | state           | 'working'                                         |
      | locked          | false                                             |
      | error           | nil                                               |
      | pending_work    | nil                                               |
      | version         | APP_VERSION                                       |
    And I should see 0 "SplitDocument" documents in the "documents" collection
    And the logs should contain "Test Split Running"
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
    When I insert 1 "PublishDocument" with a "ready" state, document_id "123", content "{'content' => 'some content'}", metadata "{'meta' => 'some meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id         | '123'                         |
      | pending_actions     | []                            |
      | dev_errors          | {}                            |
      | ops_errors          | {}                            |
      | metadata            | {'meta' => 'some meta'}       |
      | content             | {'content' => 'some content'} |
      | state               | 'published'                   |
      | locked              | false                         |
      | error               | nil                           |
      | pending_work        | nil                           |
      | version             | APP_VERSION                   |
      | title               | 'The Title'                   |
      | copyright           | 'Copyright the future'        |
      | published_timestamp | recent_timestamp              |
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
    And I insert 1 "PublishDocument" with a "published" state, document_id "123", content "{'orig_content' => 'old published content'}", metadata "{'orig_meta' => 'old published metadata'}"
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, document_id "123", content "{'new_content' => 'new content'}", metadata "{'new_meta' => 'new metadata'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id     | '123'                                                                       |
      | pending_actions | []                                                                          |
      | dev_errors      | {}                                                                          |
      | ops_errors      | {}                                                                          |
      | metadata        | {'orig_meta' => 'old published metadata', 'new_meta' => 'new metadata'}     |
      | content         | {'orig_content' => 'old published content', 'new_content' => 'new content'} |
      | state           | 'published'                                                                 |
      | locked          | false                                                                       |
      | error           | nil                                                                         |
      | pending_work    | nil                                                                         |
      | version         | APP_VERSION                                                                 |
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
    When I insert 1 "ConsumeDocument" with a "published" state, document_id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And  I should see a "ConsumeOutputDocument" in "documents" with the following
      | document_id     | 'consume_1'                                                  |
      | metadata        | {'touched_by' => ['block_1', 'block_3'], 'new' => 'block_1'} |
      | pending_actions | []                                                           |
      | dev_errors      | {}                                                           |
      | ops_errors      | {}                                                           |
      | content         | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'} |
      | state           | 'working'                                                    |
      | locked          | false                                                        |
      | error           | nil                                                          |
      | pending_work    | nil                                                          |
      | version         | APP_VERSION                                                  |
    And  I should see a "ConsumeOutputDocument" in "documents" with the following
      | document_id     | 'consume_2'                                       |
      | metadata        | {'touched_by' => ['block_2'], 'new' => 'block_2'} |
      | pending_actions | []                                                |
      | dev_errors      | {}                                                |
      | ops_errors      | {}                                                |
      | content         | {'text_2' => 'text_content_2'}                    |
      | state           | 'working'                                         |
      | locked          | false                                             |
      | error           | nil                                               |
      | pending_work    | nil                                               |
      | version         | APP_VERSION                                       |
    And I should see a "ConsumeDocument" in "documents.ConsumeDocument" with the following
      | document_id | '123'                          |
      | content     | {'text' => 'incoming content'} |
      | metadata    | {'meta' => 'incoming meta'}    |
      | state       | 'published'                    |
      | version     | APP_VERSION                    |
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
      | available_actions | unimplemented_splitter |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "UnimplementedSplitterInputDocument" with a "ready" state, document_id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "UnimplementedSplitterInputDocument" documents in the "documents" collection
    Then I should see a "UnimplementedSplitterInputDocument" in "failures" with the following
      | document_id     | '123'                                                                                                                                                                                    |
      | metadata        | {'meta' => 'incoming meta'}                                                                                                                                                              |
      | pending_actions | []                                                                                                                                                                                       |
      | dev_errors      | {'unimplemented_splitter' => [{'class' => 'Armagh::Actions::Errors::ActionMethodNotImplemented', 'message' => 'Split actions must overwrite the split method.', 'trace' => 'anything'}]} |
      | ops_errors      | {}                                                                                                                                                                                       |
      | content         | {'text' => 'incoming content'}                                                                                                                                                           |
      | state           | 'ready'                                                                                                                                                                                  |
      | locked          | false                                                                                                                                                                                    |
      | error           | true                                                                                                                                                                                     |
      | pending_work    | nil                                                                                                                                                                                      |
      | version         | APP_VERSION                                                                                                                                                                              |
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
    When I insert 1 "BadPublisherDocument" with a "ready" state, document_id "123", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "BadPublisherDocument" documents in the "documents" collection
    Then I should see a "BadPublisherDocument" in "failures" with the following
      | document_id     | '123'                                                                                                        |
      | metadata        | {'meta' => 'incoming meta'}                                                                                  |
      | pending_actions | []                                                                                                           |
      | dev_errors      | {'bad_publisher' => [{'class' => 'RuntimeError', 'message' => 'poorly implemented', 'trace' => 'anything'}]} |
      | ops_errors      | {}                                                                                                           |
      | content         | {'text' => 'incoming content'}                                                                               |
      | state           | 'ready'                                                                                                      |
      | locked          | false                                                                                                        |
      | error           | true                                                                                                         |
      | pending_work    | nil                                                                                                          |
      | version         | APP_VERSION                                                                                                  |
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
    When I insert 1 "BadConsumerDocument" with a "published" state, document_id "123", content "{'content' => 'published content'}", metadata "{'meta' => 'published metadata'}"
    And I wait 7 seconds
    Then I should see 0 "BadConsumerDocument" documents in the "failures" collection
    Then I should see a "BadConsumerDocument" in "documents.BadConsumerDocument" with the following
      | document_id     | '123'                                                                                                       |
      | metadata        | {'meta' => 'published metadata'}                                                                            |
      | pending_actions | []                                                                                                          |
      | dev_errors      | {'bad_consumer' => [{'class' => 'RuntimeError', 'message' => 'poorly implemented', 'trace' => 'anything'}]} |
      | ops_errors      | {}                                                                                                          |
      | content         | {'content' => 'published content'}                                                                          |
      | state           | 'published'                                                                                                 |
      | locked          | false                                                                                                       |
      | error           | true                                                                                                        |
      | pending_work    | nil                                                                                                         |
      | version         | APP_VERSION                                                                                                 |
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
    When I insert 1 "TooLargeInputDocType" with a "ready" state, document_id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "TooLargeCollectorOutputDocument" documents in the "documents" collection
    Then I should see a "TooLargeInputDocType" in "failures" with the following
      | document_id     | 'incoming'                                                                                                                                                                                                                                           |
      | metadata        | {'meta' => 'incoming meta'}                                                                                                                                                                                                                          |
      | pending_actions | []                                                                                                                                                                                                                                                   |
      | dev_errors      | {}                                                                                                                                                                                                                                                   |
      | ops_errors      | {'too_large_collector' => [{'class' => 'Armagh::Documents::Errors::DocumentSizeError', 'message' => 'Document [UUID] is too large.  Consider using a divider or splitter to break up the document.', 'trace' => 'anything', 'cause' => 'anything'}]} |
      | content         | {'text' => 'incoming content'}                                                                                                                                                                                                                       |
      | state           | 'ready'                                                                                                                                                                                                                                              |
      | locked          | false                                                                                                                                                                                                                                                |
      | error           | true                                                                                                                                                                                                                                                 |
      | pending_work    | nil                                                                                                                                                                                                                                                  |
      | version         | APP_VERSION                                                                                                                                                                                                                                          |
    And the logs should contain "ERROR"

  Scenario: Have a splitter that edits documents that are too large
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | too_large_splitter |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "TooLargeInputDocType" with a "ready" state, document_id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "TooLargeSplitterOutputDocument" documents in the "documents" collection
    Then I should see a "TooLargeInputDocType" in "failures" with the following
      | document_id  | 'incoming'                                                                                                                                                                                                                                             |
      | metadata     | {'meta' => 'incoming meta'}                                                                                                                                                                                                                            |
      | dev_errors   | {}                                                                                                                                                                                                                                                     |
      | ops_errors   | {'too_large_splitter' => [{'class' => 'Armagh::Documents::Errors::DocumentSizeError', 'message' => 'Document split_123 is too large.  Consider using a divider or splitter to break up the document.', 'trace' => 'anything', 'cause' => 'anything'}]} |
      | content      | {'text' => 'incoming content'}                                                                                                                                                                                                                         |
      | state        | 'ready'                                                                                                                                                                                                                                                |
      | locked       | false                                                                                                                                                                                                                                                  |
      | error        | true                                                                                                                                                                                                                                                   |
      | pending_work | nil                                                                                                                                                                                                                                                    |
      | version      | APP_VERSION                                                                                                                                                                                                                                            |
    And the logs should contain "ERROR"

  Scenario: Have a splitter that edits the current document
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | edit_current_splitter |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "EditCurrentInputDocType" with a "ready" state, document_id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 0 "EditCurrentSplitterOutputDocument" documents in the "documents" collection
    Then I should see a "EditCurrentInputDocType" in "failures" with the following
      | document_id     | 'incoming'                                                                                                                                                                                                                 |
      | metadata        | {'meta' => 'incoming meta'}                                                                                                                                                                                                |
      | pending_actions | []                                                                                                                                                                                                                         |
      | dev_errors      | {'edit_current_splitter' => [{'class' => 'Armagh::Documents::Errors::DocumentError', 'message' => 'Cannot edit document \'incoming\'.  It is the same document that was passed into the action.', 'trace' => 'anything'}]} |
      | ops_errors      | {}                                                                                                                                                                                                                         |
      | content         | {'text' => 'incoming content'}                                                                                                                                                                                             |
      | state           | 'ready'                                                                                                                                                                                                                    |
      | locked          | false                                                                                                                                                                                                                      |
      | error           | true                                                                                                                                                                                                                       |
      | pending_work    | nil                                                                                                                                                                                                                        |
      | version         | APP_VERSION                                                                                                                                                                                                                |
    And the logs should contain "ERROR"

  Scenario: Have a splitter that has an error during document update
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | update_error_splitter |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "UpdateErrorSplitterOutputDocument" with a "working" state, document_id "update_id", content "{'existing_content'=>'some content'}", metadata "{'existing_metadata'=>'some meta'}"
    And I insert 1 "UpdateErrorInputDocType" with a "ready" state, document_id "incoming", content "{'text' => 'incoming content'}", metadata "{'meta' => 'incoming meta'}"
    And I wait 7 seconds
    Then I should see 1 "UpdateErrorSplitterOutputDocument" documents in the "documents" collection
    And I should see a "UpdateErrorInputDocType" in "failures" with the following
      | document_id     | 'incoming'                                                                                                |
      | metadata        | {'meta' => 'incoming meta'}                                                                               |
      | pending_actions | []                                                                                                        |
      | dev_errors      | {'update_error_splitter' => [{'class' => 'RuntimeError', 'message' => 'Failure', 'trace' => 'anything'}]} |
      | ops_errors      | {}                                                                                                        |
      | content         | {'text' => 'incoming content'}                                                                            |
      | state           | 'ready'                                                                                                   |
      | locked          | false                                                                                                     |
      | error           | true                                                                                                      |
      | pending_work    | nil                                                                                                       |
      | version         | APP_VERSION                                                                                               |
    And I should see a "UpdateErrorSplitterOutputDocument" in "documents" with the following
      | document_id     | 'update_id'                            |
      | metadata        | {'existing_metadata'=>'some meta'}     |
      | pending_actions | []                                     |
      | dev_errors      | {}                                     |
      | ops_errors      | {}                                     |
      | content         | {'existing_content' => 'some content'} |
      | state           | 'working'                              |
      | locked          | false                                  |
      | error           | nil                                    |
      | pending_work    | nil                                    |
    And the logs should contain "ERROR"

  Scenario: Have a consumer that has a dev error
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | notify_dev |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "NotifyDevDocType" with a "ready" state, document_id "id", content "{'existing_content'=>'some content'}", metadata "{'existing_metadata'=>'some meta'}"
    And I wait 7 seconds
    And I should see a "NotifyDevDocType" in "failures" with the following
      | document_id     | 'id'                                           |
      | metadata        | {'existing_metadata'=>'some meta'}             |
      | pending_actions | []                                             |
      | dev_errors      | {'notify_dev' => [{'message' => 'Dev Error'}]} |
      | ops_errors      | {}                                             |
      | content         | {'existing_content'=>'some content'}           |
      | state           | 'ready'                                        |
      | locked          | false                                          |
      | error           | true                                           |
      | pending_work    | nil                                            |
      | version         | APP_VERSION                                    |
    And the logs should contain "DEV_ERROR"
    And the logs should contain "Test Split Notify Dev Complete"

  Scenario: Have a consumer that has an ops error
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | notify_ops |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "NotifyOpsDocType" with a "ready" state, document_id "id", content "{'existing_content'=>'some content'}", metadata "{'existing_metadata'=>'some meta'}"
    And I wait 7 seconds
    And I should see a "NotifyOpsDocType" in "failures" with the following
      | document_id     | 'id'                                           |
      | metadata        | {'existing_metadata'=>'some meta'}             |
      | pending_actions | []                                             |
      | ops_errors      | {'notify_ops' => [{'message' => 'Ops Error'}]} |
      | dev_errors      | {}                                             |
      | content         | {'existing_content'=>'some content'}           |
      | state           | 'ready'                                        |
      | locked          | false                                          |
      | error           | true                                           |
      | pending_work    | nil                                            |
      | version         | APP_VERSION                                    |
    And the logs should contain "OPS_ERROR"
    And the logs should contain "Test Split Notify Ops Complete"

  Scenario: Have a document for a publisher that changes the document ID
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | change_id_publisher |
    And I run armagh
    And I wait 3 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, document_id "old_id", content "{'content' => 'some content'}", metadata "{'meta' => 'some meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And I should see 1 "PublishDocument" documents in the "documents.PublishDocument" collection
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id         | 'new_id'                      |
      | pending_actions     | []                            |
      | dev_errors          | {}                            |
      | ops_errors          | {}                            |
      | metadata            | {'meta' => 'some meta'}       |
      | content             | {'content' => 'some content'} |
      | state               | 'published'                   |
      | locked              | false                         |
      | error               | nil                           |
      | pending_work        | nil                           |
      | version             | APP_VERSION                   |
      | title               | 'The Title'                   |
      | copyright           | 'Copyright the future'        |
      | published_timestamp | recent_timestamp              |
    And the logs should contain "Test Change ID Publish Running "
    And the logs should not contain "ERROR"
    And I should see 0 "PublishDocument" documents in the "documents" collection

  Scenario: Have a document for a publisher that changes the document ID to an existing ID
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | change_id_publisher |
    And I run armagh
    And I wait 3 seconds
    And I insert 1 "PublishDocument" with a "published" state, document_id "new_id", content "{'orig_content' => 'old published content'}", metadata "{'orig_meta' => 'old published metadata'}"
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 "PublishDocument" with a "ready" state, document_id "old_id", content "{'new_content' => 'new content'}", metadata "{'new_meta' => 'new meta'}"
    Then I should see an agent with a status of "running" within 10 seconds
    Then I should see an agent with a status of "idle" within 10 seconds
    And I should see 1 "PublishDocument" documents in the "documents.PublishDocument" collection
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id         | 'new_id'                                                                    |
      | pending_actions     | []                                                                          |
      | dev_errors          | {}                                                                          |
      | ops_errors          | {}                                                                          |
      | metadata            | {'orig_meta' => 'old published metadata', 'new_meta' => 'new meta'}         |
      | content             | {'orig_content' => 'old published content', 'new_content' => 'new content'} |
      | state               | 'published'                                                                 |
      | locked              | false                                                                       |
      | error               | nil                                                                         |
      | pending_work        | nil                                                                         |
      | version             | APP_VERSION                                                                 |
      | title               | 'The Title'                                                                 |
      | copyright           | 'Copyright the future'                                                      |
      | published_timestamp | recent_timestamp                                                            |
    And the logs should contain "Test Change ID Publish Running "
    And the logs should not contain "ERROR"
    And I should see 0 "PublishDocument" documents in the "documents" collection

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
    When I insert 1 "CollectDocument" with a "ready" state, document_id "collect_id", content "{'doesnt_matter' => true}", metadata "{}"
    And I wait 30 seconds
    Then the logs should contain "Test Collect Running"
    And the logs should contain "Test Divider Running"
    And the logs should contain "Test Consume Running"
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"
    And I should see a "ConsumeOutputDocument" in "documents" with the following
      | document_id         | 'consume_1'                                                                     |
      | state               | 'ready'                                                                         |
      | locked              | false                                                                           |
      | error               | nil                                                                             |
      | pending_work        | nil                                                                             |
      | version             | APP_VERSION                                                                     |
      | collection_task_ids | ['collect_id']                                                                  |
      | metadata            | {'touched_by' => ['block_1','block_3','block_1','block_3'], 'new' => 'block_1'} |
      | content             | {'text_1' => 'text_content_1', 'text_3' => 'text_content_3'}                    |
    And I should see a "ConsumeOutputDocument" in "documents" with the following
      | document_id         | 'consume_2'                                                 |
      | state               | 'ready'                                                     |
      | locked              | false                                                       |
      | error               | nil                                                         |
      | pending_work        | nil                                                         |
      | version             | APP_VERSION                                                 |
      | collection_task_ids | ['collect_id']                                              |
      | metadata            | {"touched_by" => ["block_2","block_2"], "new" => "block_2"} |
      | content             | {"text_2" => "text_content_2"}                              |
    And I should see a "Document" in "documents.Document" with the following
      | document_id         | 'split_1'                                                   |
      | state               | 'published'                                                 |
      | locked              | false                                                       |
      | error               | nil                                                         |
      | pending_work        | nil                                                         |
      | version             | APP_VERSION                                                 |
      | collection_task_ids | ['collect_id']                                              |
      | metadata            | {"touched_by" => ["block_1","block_3"], "new" => "block_1"} |
      | content             | {"text_1"=> "text_content_1","text_3"=> "text_content_3"}   |
      | copyright           | 'Copyright the future'                                      |
      | title               | 'The Title'                                                 |
    And I should see a "Document" in "documents.Document" with the following
      | document_id         | 'split_2'                                        |
      | state               | 'published'                                      |
      | locked              | false                                            |
      | failure             | nil                                              |
      | pending_work        | nil                                              |
      | version             | APP_VERSION                                      |
      | collection_task_ids | ['collect_id']                                   |
      | metadata            | {"touched_by" => ["block_2"], "new"=> "block_2"} |
      | content             | {"text_2" => "text_content_2"}                   |
      | copyright           | 'Copyright the future'                           |
      | title               | 'The Title'                                      |
    And I should see a "CollectedDocument" in "documents" with the following
      | document_id         | '[UUID]'       |
      | state               | 'ready'        |
      | locked              | false          |
      | error               | nil            |
      | pending_work        | nil            |
      | version             | APP_VERSION    |
      | collection_task_ids | ['collect_id'] |
      | metadata            | {}             |
      | content             | {'bson_binary' => BSON::Binary.new('collected content')}             |
    And I should see a "CollectDocument" in "archive" with the following
      | document_id     | 'collect_id'              |
      | metadata        | {'docs_collected' => 2}   |
      | pending_actions | []                        |
      | dev_errors      | {}                        |
      | ops_errors      | {}                        |
      | content         | {'doesnt_matter' => true} |
      | state           | 'ready'                   |
      | locked          | false                     |
      | error           | nil                       |
      | pending_work    | nil                       |
      | version         | APP_VERSION               |
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
    And I insert 1 "PublishDocument" with a "published" state, document_id "123", content "{'orig_content' => 'old published content'}", metadata "{'orig_meta' => 'old published metadata'}"
    And I set all "documents.PublishDocument" documents to have the following
      | version | 'old_version' |
    Then  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id | '123'         |
      | version     | 'old_version' |
    When I insert 1 "PublishDocument" with a "ready" state, document_id "123", content "{'new_content' => 'new content'}", metadata "{'new_meta' => 'new meta'}"
    And I run armagh
    And I wait 30 seconds
    And  I should see a "PublishDocument" in "documents.PublishDocument" with the following
      | document_id | '123'       |
      | version     | APP_VERSION |
    And the logs should contain "Test Publish Running"
    And the logs should not contain "ERROR"