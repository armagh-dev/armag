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

def replace_trace(hash)
  hash['trace'] = 'placeholder' if hash['trace']
  hash['cause'] = 'placeholder' if hash['cause']
end

def replace_ts(hash)
  hash['timestamp'] = 'placeholder'
end

def clean_string(str)
  str.gsub!(/\w{8}-\w{4}-\w{4}-\w{4}-\w{12}/, '[UUID]')
  str.gsub!(/-[a-zA-Z0-9]{#{Armagh::Support::Random::RANDOM_ID_LENGTH-5},#{Armagh::Support::Random::RANDOM_ID_LENGTH}}/, '-[ID]')
  str.gsub!(/\/[a-zA-Z0-9]{#{Armagh::Support::Random::RANDOM_ID_LENGTH-5},#{Armagh::Support::Random::RANDOM_ID_LENGTH}}/, '/[ID]')
  str
end

def recent_timestamp
  :recent_timestamp
end

def not_empty
  :not_empty
end

When(/^I should see a "([^"]*)" in "([^"]*)" with the following$/) do |doc_type, collection, table|
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
          expected.collect do |_k, v|
            if v.is_a? Hash
              replace_trace v
              replace_ts v
            elsif v.is_a? Array
              v.each do |i|
                if i.is_a? Hash
                  replace_trace i
                  replace_ts i
                end
              end
            end
          end

          doc[key].collect do |_k, v|
            if v.is_a? Hash
              replace_trace v
              replace_ts v
              v.values.each {|vv| clean_string(vv) if vv.is_a? String}
            elsif v.is_a? Array
              v.each do |i|
                if i.is_a? Hash
                  replace_trace(i)
                  replace_ts i
                  i.values.each do |val|
                    clean_string(val) if val.is_a? String
                    if val.is_a? Array
                      val.each do |vv|
                        clean_string(vv) if vv.is_a? String
                      end
                    end
                  end
                end
                clean_string(i) if i.is_a? String
              end
            elsif v.is_a? String
              clean_string(v)
            end
          end
        end

        actual = doc[key]

        if expected == not_empty
          if actual.compact.empty?
            doc_problems[doc_id][key] = "'#{expected.to_s}' !~~ '#{actual.to_s}'"
            found_matching_doc = false
            next
          end
        elsif expected == recent_timestamp
          now = Time.now
          if now - doc[key] > 60
            doc_problems[doc_id][key] = "'#{now}' !~~ '#{actual.to_s}'"
            found_matching_doc = false
            next
          end
        else
          clean_string(actual) if actual.is_a? String

          if expected != actual
            doc_problems[doc_id][key] = "'#{expected.to_s}' != '#{actual.to_s}'"
            found_matching_doc = false
            next
          end
        end
      end
    end
    break if found_matching_doc
  end

  assert_true(found_matching_doc, "No #{doc_type} was found with the expected values.  Details: #{doc_problems}")
end

And(/^I should see (\d+) "([^"]*)" documents in the "([^"]*)" collection$/) do |count, doc_type, doc_collection|
  expected_count = count.to_i
  num_found = 0

  MongoSupport.instance.get_mongo_documents(doc_collection).each do |doc|
    num_found += 1 if doc['type'] == doc_type
  end

  assert_equal(expected_count, num_found)
end
