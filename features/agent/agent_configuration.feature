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
Feature: Agent Configuration
  Instead of configuring each agent at runtime
  I want to be able to change their configuration dynamically

  Scenario: Initial log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's launcher config is
      | log_level         | info |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 1 seconds
    Then the logs should contain 'INFO'
    But the logs should not contain 'DEBUG'

  Scenario: Increase log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's launcher config is
      | log_level         | warn |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 1 seconds
    Then the logs should contain 'WARN'
    But the logs should not contain 'INFO'
    And the logs should not contain 'DEBUG'
    When armagh's launcher config is
      | log_level         | info |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:01:00 |
    And I wait 1 seconds
    And the logs are emptied
    And I wait 5 seconds
    Then the logs should not contain 'DEBUG'
    But the logs should contain 'INFO'

  Scenario: Decrease log level
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    And the logs are emptied
    When armagh's launcher config is
      | log_level         | debug |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:00:00 |
    And I run armagh
    And I wait 1 seconds
    Then the logs should contain 'DEBUG'
    And the logs should contain 'INFO'
    And the logs should contain 'WARN'
    When armagh's launcher config is
      | log_level         | warn |
      | checkin_frequency | 1 |
      | timestamp         | 2015-01-01 11:01:00 |
    And I wait 1 seconds
    And the logs are emptied
    And I wait 5 seconds
    Then the logs should not contain 'DEBUG'
    And the logs should not contain 'INFO'
    But the logs should contain 'WARN'