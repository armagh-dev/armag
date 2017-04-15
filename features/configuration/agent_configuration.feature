# Copyright 2017 Noragh Analytics, Inc.
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
      | log_level         | error |
      | checkin_frequency | 1     |
    And armagh's "agent" config is
      | log_level | debug |
    And I run armagh
    Then I should see an agent with a status of "idle" within 30 seconds
    And the logs should contain "DEBUG"

  Scenario: Default log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | error |
      | checkin_frequency | 1     |
    And I run armagh
    Then I should see an agent with a status of "idle" within 30 seconds
    Then the logs should contain "INFO"
    But the logs should not contain "DEBUG"

  Scenario: Change log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's "launcher" config is
      | log_level         | error |
      | checkin_frequency | 1     |
    And armagh's "agent" config is
      | log_level | warn |
    And I run armagh
    Then I should see an agent with a status of "idle" within 30 seconds
    Then the logs should contain "WARN"
    But the logs should not contain "INFO"
    And the logs should not contain "DEBUG"
    When the logs are emptied
    And armagh's "launcher" config is
      | log_level         | error |
      | checkin_frequency | 1     |
    And armagh's "agent" config is
      | log_level | info |
    When the logs are emptied
    And I wait 10 seconds
    Then the logs should not contain "DEBUG"
    But the logs should contain "INFO"