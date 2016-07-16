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

When(/^I insert (\d+) "([^"]*)" with a "([^"]*)" state, document_id "([^"]*)", content "([^"]*)", metadata "([^"]*)"$/) do |count, doc_type, state, document_id, content, meta|
  docspec = Armagh::Documents::DocSpec.new(doc_type, state)
  pending_actions = @action_manager.get_action_names_for_docspec docspec

  content = content.nil? ? {} : eval(content)
  meta = meta.nil? ? {} : eval(meta)

  Armagh::Document.version.merge! APP_VERSION

  count.to_i.times do
    Armagh::Document.create(type: doc_type, draft_content: content, published_content: {}, draft_metadata: meta,
                            published_metadata: {}, pending_actions: pending_actions, state: state, document_id: document_id, document_timestamp: nil, collection_task_ids: [], new: true)
  end
end

When(/^I insert (\d+) "([^"]*)" with a "([^"]*)" state, document_id "([^"]*)", published content "([^"]*)", published metadata "([^"]*)"$/) do |count, doc_type, state, document_id, content, meta|
  docspec = Armagh::Documents::DocSpec.new(doc_type, state)
  pending_actions = @action_manager.get_action_names_for_docspec docspec

  content = content.nil? ? {} : eval(content)
  meta = meta.nil? ? {} : eval(meta)

  count.to_i.times do
    Armagh::Document.create(type: doc_type, draft_content: {}, published_content: content, draft_metadata: {},
                            published_metadata: meta, pending_actions: pending_actions, state: state, document_id: document_id, document_timestamp: nil, collection_task_ids: [], new: true)
  end
end

And(/^I set all "([^"]*)" documents to have the following$/) do |collection, table|
  new_doc_info = table.rows_hash
  new_doc_info.each{|k,v| new_doc_info[k] = eval(v)}

  MongoSupport.instance.get_mongo_documents(collection).each do |document|
    MongoSupport.instance.update_document(collection, document['_id'], new_doc_info)
  end
end