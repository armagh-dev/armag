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

Then(/^I should see a "([^"]*)" with (\d+) pending actions*$/) do |doc_type, num_actions|
  num_actions = num_actions.to_i

  found_matching_doc = false

  MongoSupport.instance.get_documents.each do |doc|
    if doc['type'] == doc_type && doc['pending_actions'].length == num_actions
      found_matching_doc = true
      break
    end
  end

  assert_true(found_matching_doc, "No #{doc_type} was found with #{num_actions} pending actions")
end