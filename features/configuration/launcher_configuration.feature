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

  Scenario: Launch 0 agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents | 0 |
    And I run armagh
    Then the number of running agents equals 0

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

  Scenario: Increase number of agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 2                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And the number of running agents equals 2
    When armagh's "launcher" config is
      | num_agents        | 4                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:01 |
    And I wait 5 seconds
    Then the number of running agents equals 4

  Scenario: Decrease number of agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 4                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And the number of running agents equals 4
    When armagh's "launcher" config is
      | num_agents        | 2                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:01 |
    And I wait 5 seconds
    Then the number of running agents equals 2

  Scenario: Create an older configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 4                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And the number of running agents equals 4
    When armagh's "launcher" config is
      | num_agents        | 2                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 10:00:00 |
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

  Scenario: Start with an invalid launcher configuration
    Given armagh isn't already running
    And the logs are emptied
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | -100                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 2 seconds
    Then armagh should have exited
    And the logs should contain "Invalid initial launcher configuration.  Exiting."

  Scenario: Start with a partial launcher configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 2 seconds
    Then the number of running agents equals 1

  Scenario: Switch to invalid launcher configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | log_level         | debug               |
      | num_agents        | 4                   |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 2 seconds
    Then the number of running agents equals 4
    When armagh's "launcher" config is
      | log_level         | info                |
      | num_agents        | 1                   |
      | checkin_frequency | -1                  |
      | timestamp         | 2015-01-01 11:00:00 |
    And I wait 2 seconds
    Then the number of running agents equals 4
