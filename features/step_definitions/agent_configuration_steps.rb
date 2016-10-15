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

require_relative '../support/log_support'

Given(/^the logs are emptied/) do
  LogSupport.empty_logs
end

Then(/^the logs should not contain "([^"]*)"$/) do |string|
  bad_files = []

  LogSupport.each_log do |file|
    bad_files << file if File.read(file).include?(string)
  end

  assert_empty(bad_files, "Files containing #{string}: #{bad_files}")
end

Then(/^the logs should contain "([^"]*)"$/) do |string|
  found_string = false

  LogSupport.each_log do |file|
    if File.read(file) =~ /#{string}/
      found_string = true
      break
    end
  end

  assert_true(found_string)
end
