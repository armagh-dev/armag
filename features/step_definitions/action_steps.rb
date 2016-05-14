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

And(/^I should see a "([^"]*)" in "([^"]*)" with the following$/) do |doc_type, collection, table|
  doc_info = table.rows_hash
  found_matching_doc = false
  doc_problems = {}

  MongoSupport.instance.get_mongo_documents(collection).each do |doc|
    if doc['type'] == doc_type
      doc_id = doc['_id']
      doc_problems[doc_id] = {}
      found_matching_doc = true
      doc_info.each do |key, value|
        # This is a potential match
        expected = eval(value)

        if expected.is_a?(Hash) && doc[key].is_a?(Hash)
          expected.collect{|_k,v| v['trace'] = 'placeholder' if v.is_a?(Hash) && v['trace']}
          doc[key].collect{|_k,v| v['trace'] = 'placeholder' if v.is_a?(Hash) && v['trace']}

          expected.collect{|_k,v| v['cause'] = 'placeholder' if v.is_a?(Hash) && v['cause']}
          doc[key].collect{|_k,v| v['cause'] = 'placeholder' if v.is_a?(Hash) && v['cause']}
        end

        if expected != doc[key]
          doc_problems[doc_id][key] = "#{expected.to_s} != #{doc[key].to_s}"
          found_matching_doc = false
          next
        end
      end
    end
    break if found_matching_doc
  end

  assert_true(found_matching_doc, "No #{doc_type} was found with the expected values.  Details: #{doc_problems}")
end

When(/^I insert the following document$/) do |table|
  doc_info = table.rows_hash

  doc_info.each {|k, v| doc_info[k] = eval(v)}

  Armagh::Document.create(doc_info['type'], doc_info['content'], doc_info['meta'], doc_info['pending_actions'], doc_info['state'], doc_info['id'])
end

And(/^I should see (\d+) "([^"]*)" documents in the "([^"]*)" collection$/) do |count, doc_type, doc_collection|
  expected_count = count.to_i
  num_found = 0

  MongoSupport.instance.get_mongo_documents(doc_collection).each do |doc|
    num_found += 1 if doc['type'] == doc_type
  end

  assert_equal(expected_count, num_found)
end
