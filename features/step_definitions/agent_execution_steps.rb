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

require_relative '../../lib/document/document'
require 'armagh/documents/doc_state'

When(/^I insert (\d+) "([^"]*)" with a "([^"]*)" state, id "([^"]*)", and content "([^"]*)"$/) do |count, doc_type, state, id, content|
  docspec = Armagh::DocSpec.new(doc_type, state)
  pending_actions = @action_manager.get_action_names_for_docspec docspec

  content = content.nil? ? {} : eval(content)

  Armagh::Document.version.merge! APP_VERSION

  count.to_i.times do
    Armagh::Document.create(doc_type, content, {}, {}, pending_actions, state, id)
  end
end

When(/^I insert (\d+) "([^"]*)" with a "([^"]*)" state, id "([^"]*)", and published content "([^"]*)"$/) do |count, doc_type, state, id, content|
  docspec = Armagh::DocSpec.new(doc_type, state)
  pending_actions = @action_manager.get_action_names_for_docspec docspec

  content = content.nil? ? {} : eval(content)

  count.to_i.times do
    Armagh::Document.create(doc_type, {}, content, {}, pending_actions, state, id)
  end
end

And(/^I set all "([^"]*)" documents to have the following$/) do |collection, table|
  new_doc_info = table.rows_hash
  new_doc_info.each{|k,v| new_doc_info[k] = eval(v)}

  MongoSupport.instance.get_mongo_documents(collection).each do |document|
    MongoSupport.instance.update_document(collection, document['_id'], new_doc_info)
  end
end