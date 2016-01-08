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

@agent
Feature: Agent Launcher
  Instead of launching agents manually
  I want armagh to launch them for me

  Scenario: Launch 0 agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 0 |
    And I run armagh
    Then the number of running agents equals 0

  Scenario: Launch 2 agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 2 |
    And I run armagh
    Then the number of running agents equals 2

  Scenario: Launch default agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh doesn't have a launcher config
    And I run armagh
    Then the number of running agents equals 1

  Scenario: Increase number of agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 2 |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And the number of running agents equals 2
    When armagh's launcher config is
      | num_agents        | 4 |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:01 |
    And I wait 5 seconds
    Then the number of running agents equals 4

  Scenario: Decrease number of agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 4 |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And the number of running agents equals 4
    When armagh's launcher config is
      | num_agents        | 2 |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:01 |
    And I wait 5 seconds
    Then the number of running agents equals 2

  Scenario: Handle agents that die
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's launcher config is
      | num_agents        | 3 |
    And I run armagh
    And an agent is killed
    Then a new agent shall launch to take its place

  Scenario: Run as a daemon
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And I run armagh as a daemon
    Then armagh should run in the background
    And the number of running agents equals 1
    And the armagh daemon can be stopped

  Scenario: Handle daemon that dies
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When I run armagh as a daemon
    And the armagh daemon is killed
    And I wait 60 seconds
    Then a new daemon shall take its place

  Scenario: Unable to connect to database
    Given armagh isn't already running
    And mongo isn't running
    When I run armagh
    Then armagh should have exited
    And stderr should contain "Unable to establish connection to the database."
