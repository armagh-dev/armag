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

@agent @config
Feature: Agent Configuration
  Instead of configuring each agent at runtime
  I want to be able to change their configuration dynamically

  Scenario: Initial log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | info                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | log_level | info                |
      | timestamp | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "INFO"
    But the logs should not contain "DEBUG"

  Scenario: Default log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | timestamp | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "DEBUG"

  Scenario: Increase log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | log_level | warn                |
      | timestamp | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "WARN"
    But the logs should not contain "INFO"
    And the logs should not contain "DEBUG"
    When armagh's "launcher" config is
      | log_level         | info                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:01:00 |
    And armagh's "agent" config is
      | log_level | info                |
      | timestamp | 2015-01-01 11:01:00 |
    And I wait 3 seconds
    And the logs are emptied
    And I wait 7 seconds
    Then the logs should not contain "DEBUG"
    But the logs should contain "INFO"

  Scenario: Create an older configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | log_level | warn                |
      | timestamp | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "WARN"
    But the logs should not contain "INFO"
    And the logs should not contain "DEBUG"
    And armagh's "agent" config is
      | log_level | debug               |
      | timestamp | 2015-01-01 10:00:00 |
    And I wait 7 seconds
    Then the logs should not contain "DEBUG"
    And the logs should not contain "INFO"

  Scenario: Start with an invalid agent configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | log_level         | warn                |
      | timestamp         | 2015-01-01 11:00:00 |
      | available_actions | no_such_action      |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "Class 'Armagh::CustomActions::NoSuchAction' from action 'no_such_action' does not exist."
    And the logs should contain "Invalid initial agent configuration.  Exiting."

  Scenario: Start with a partial agent configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | timestamp | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "Partial agent configuration found.  Using default values for available_actions, log_level."

  Scenario: Switch to invalid agent configuration
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | timestamp         | 2015-01-01 11:00:00 |
      | log_level         | debug               |
      | available_actions |                     |
    And I run armagh
    And I wait 3 seconds
    And armagh's "agent" config is
      | timestamp         | 2015-01-01 11:00:00 |
      | log_level         | debug               |
      | available_actions | no_such_action      |
    And I wait 3 seconds
    Then armagh should be running
    And the logs should contain "Ignoring agent configuration update."

  Scenario: Start with an agent configuration with warnings
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | warn                |
      | checkin_frequency | 1                   |
      | timestamp         | 2015-01-01 11:00:00 |
    And armagh's "agent" config is
      | timestamp         | 2015-01-01 11:00:00 |
      | log_level         | debug               |
      | available_actions |                     |
    And I run armagh
    And I wait 3 seconds
    And armagh's "agent" config is
      | timestamp         | 2015-01-01 11:00:00 |
      | log_level         | debug               |
      | available_actions | no_such_action      |
    And I wait 3 seconds
    Then the logs should contain "agent configuration validation is usable but had warnings:"
    And the logs should contain "Action Configuration is empty."


