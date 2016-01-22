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
Feature: Agent Status
  I want armagh to report launcher and agent status

  Scenario: Report status with no agents
    Given armagh isn't already running
    And mongo is running
    And mongo is clean
    When armagh's "launcher" config is
      | num_agents        | 0 |
      | checkin_frequency | 1 |
    And I run armagh
    And I wait 2 seconds
    Then the valid reported status should contain agents with statuses
      | nil |

  # Other 'status reporting' type features are tested in the agent_tasks feature