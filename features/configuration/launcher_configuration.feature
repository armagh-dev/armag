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

@config @agent @launcher
Feature: Launcher Configuration
  Instead of configuring the launcher at runtime
  I want to be able to change its configuration dynamically

  Scenario: Launch 2 agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents | 2 |
    And I run armagh
    Then the number of running agents equals 2

  Scenario: Launch default agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh doesn't have a "launcher" config
    And I run armagh
    Then the number of running agents equals 1

  Scenario: Change number of agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 2 |
      | checkin_frequency | 1 |
    And I run armagh
    And the number of running agents equals 2
    When armagh's "launcher" config is
      | num_agents        | 4 |
      | checkin_frequency | 1 |
    And I wait 5 seconds
    Then the number of running agents equals 4

  Scenario: Handle agents that die
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents | 3 |
    And I run armagh
    And an agent is killed
    Then a new agent shall launch to take its place

  Scenario: Initial log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | debug |
      | checkin_frequency | 1     |
    And armagh's "agent" config is
      | log_level | error |
    And I run armagh
    And I wait 1 second
    Then the logs should contain "DEBUG"

  Scenario: Default log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | checkin_frequency | 1 |
    And armagh's "agent" config is
      | log_level | error |
    And I run armagh
    And I wait 1 second
    Then the logs should contain "INFO"
    But the logs should not contain "DEBUG"

  Scenario: Change log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn |
      | checkin_frequency | 1    |
    And armagh's "agent" config is
      | log_level | error |
    And I run armagh
    And I wait 1 second
    Then the logs should contain "WARN"
    But the logs should not contain "INFO"
    And the logs should not contain "DEBUG"
    When the logs are emptied
    And armagh's "launcher" config is
      | log_level         | info |
      | checkin_frequency | 1    |
    When the logs are emptied
    And I wait 3 seconds
    Then the logs should not contain "DEBUG"
    But the logs should contain "INFO"

  Scenario: Change action configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "action" config is
      | iteration         | 1 |
    And I run armagh
    And I wait 3 seconds
    When the logs are emptied
    When armagh's "action" config is
      | iteration         | 2 |
    And I wait 61 seconds
    Then the logs should contain "Configuration change detected"
