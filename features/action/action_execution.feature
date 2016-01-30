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

  Scenario: Have a document to work on
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | sleep_action |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action" processing with a "published" state
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And I should see a "TestDocumentInput" with the following
      | pending_actions | [] |
      | failed_actions  | {}                      |
    And I should see a "TestDocumentOutput" with the following
      | pending_actions | [] |
      | failed_actions  | {}                      |

  Scenario: Have a document to work on with defaults
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | sleep_action_default |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action_default" processing with a "published" state
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And I should see a "SleepInputDocument" with the following
      | pending_actions | [] |
      | failed_actions  | {} |
    And I should see a "SleepOutputDocument" with the following
      | pending_actions | [] |
      | failed_actions  | {} |

  Scenario: I have a document to work on with an action that is unavailable
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | non_existent_action |
    And I run armagh
    And I wait 2 second
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "non_existent_action" processing with a "published" state
    And I wait 5 seconds
    Then I should see a "TestDocumentInput" with the following
      | pending_actions | [] |
      | failed_actions  | {"non_existent_action"=>{"message"=>"Undefined action"}} |

  Scenario: Have a document to work on with an action that has no execute
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | no_execution_action |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "no_execution_action" processing with a "published" state
    And I wait 5 seconds
    Then I should see a "TestDocumentInput" with the following
      | pending_actions | [] |
      | failed_actions  | {"no_execution_action"=>{"message"=>"The execute method needs to be overwritten by Armagh::ClientActions::NoExecutionAction", "trace"=>"anything"}} |

  Scenario: Have a document to work on with an action that fails in the middle
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | middle_fail_action |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "middle_fail_action" processing with a "published" state
    And I wait 5 seconds
    Then I should see a "TestDocumentInput" with the following
      | pending_actions | [] |
      | failed_actions  | {"middle_fail_action"=>{"message"=>"Ran into a problem.  Bailing", "trace"=>"anything"}} |
    And I should see 5 "TestDocumentOutput" documents

  Scenario: Don't process any documents that are closed
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | sleep_action_default |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action_default" processing with a "closed" state
    And I wait 2 seconds
    Then I should see a "SleepInputDocument" with the following
      | pending_work | true |
    And I should see 0 "SleepOutputDocument" documents

  Scenario: Don't process any documents that are pending
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | sleep_action_default |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action_default" processing with a "pending" state
    And I wait 2 seconds
    Then I should see a "SleepInputDocument" with the following
      | pending_work | true |
    And I should see 0 "SleepOutputDocument" documents

  Scenario: Execute an action that works on external documents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | available_actions | external_document_action |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "external_document_action" processing with a "published" state
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 30 seconds
    And I should see a "ExternalDocument" with the following
      | _id     | 'external_1'                                |
      | locked  | false                                        |
      | state   | Armagh::DocState::PENDING                   |
      | content | 'Document created by modify in iteration 0' |
      | meta    | {"doc_created_iteration" => 0, "1" => "Iteration 1", "2" => "Iteration 2", "3" => "Iteration 3", "4" => "Iteration 4"} |
    And I should see a "ExternalDocument" with the following
      | _id     | 'external_2'                                 |
      | locked  | false                                        |
      | state   | Armagh::DocState::PENDING                    |
      | content | 'Document created by modify! in iteration 0' |
      | meta    | {"doc_created_iteration" => 0, "1" => "Iteration 1", "2" => "Iteration 2", "3" => "Iteration 3", "4" => "Iteration 4"} |
    And I should see a "ExternalDocument" with the following
      | _id     | 'external_3'                   |
      | locked  | false                          |
      | state   | Armagh::DocState::PENDING      |
      | content | 'Document created for locking' |
      | meta    | {"lock_thread_1" => 1, "lock_thread_2" => 2, "bang_lock_thread_1" => true, "mixed_a_lock_thread_1" => true, "mixed_b_lock_thread_1" => 1, "mixed_b_lock_thread_2" => 2} |
