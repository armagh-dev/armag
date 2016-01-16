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
    When armagh's launcher config is
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
    When armagh's launcher config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
      | available_actions | sleep_action |
    And I run armagh
    And I wait 2 second
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action" processing
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And I should see a "TestDocumentInput" with 0 pending actions
    And I should see a "TestDocumentOutput" with 0 pending action

  Scenario: Have a document to work on with defaults
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 1 |
      | checkin_frequency | 1 |
      | available_actions | sleep_action_default |
    And I run armagh
    And I wait 2 second
    Then the valid reported status should contain agents with statuses
      | idle |
    When I insert 1 document for "sleep_action_default" processing
    Then I should see an agent with a status of "running" within 5 seconds
    Then I should see an agent with a status of "idle" within 5 seconds
    And I should see a "SleepInputDocument" with 0 pending actions
    And I should see a "SleepOutputDocument" with 0 pending action
