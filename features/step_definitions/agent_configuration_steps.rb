# Copyright 2018 Noragh Analytics, Inc.
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

require_relative '../support/log_support'

Given(/^the logs are emptied/) do
  LogSupport.empty_logs
end

Then(/^the logs should not contain "([^"]*)"$/) do |string|
  assert_equal(0, LogSupport.count(string), "Logs unexpectedly contained the string '#{string}'.")
end

Then(/^the logs should contain "([^"]*)"$/) do |string|
  assert_not_equal(0, LogSupport.count(string), "Logs did not contain the string '#{string}'.")
end


Then(/^the logs should contain (\d+) "([^"]*)"$/) do |count, string|
  assert_equal(count.to_i, LogSupport.count(string), "Logs did not contain the string '#{string}' #{count} times.")
end