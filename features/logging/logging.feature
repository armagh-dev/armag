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

Feature: Logging Support
  I want messages to be logged

  Scenario: Log to Mongo and Files
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 1     |
      | checkin_frequency | 1     |
      | log_level         | debug |
    And armagh's "agent" config is
      | log_level | debug |
    And I run armagh
    And I wait 3 seconds
    Then the logs should contain "DEBUG"
    And the logs should contain "INFO"
    And the logs should contain "ANY"
    And I should see a Document in "log" with the following
      | level | DEBUG |
    And I should see a Document in "log" with the following
      | level | INFO |
    And I should see a Document in "log" with the following
      | level | ANY |