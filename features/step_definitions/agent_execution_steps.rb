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

require_relative '../../lib/models/document'
require_relative '../../lib/actions/workflow'
require_relative '../../lib/logging'

When(/^I insert (\d+) "([^"]*)" with a "([^"]*)" state, document_id "([^"]*)", content "([^"]*)", metadata "([^"]*)"$/) do |count, doc_type, state, document_id, content, meta|
  @logger ||= Armagh::Logging.set_logger('Armagh::Application::Test::AgentExecution')
  @workflow ||= Armagh::Actions::Workflow.new(@logger, Armagh::Connection.config)

  docspec = Armagh::Documents::DocSpec.new(doc_type, state)
  pending_actions = @workflow.get_action_names_for_docspec(docspec)

  content = content.nil? ? {} : eval(content)
  meta = meta.nil? ? {} : eval(meta)

  Armagh::Models::Document.version.merge! APP_VERSION

  count.to_i.times do
    Armagh::Models::Document.create(type: doc_type, content: content, metadata: meta,
                            pending_actions: pending_actions, state: state, document_id: document_id, document_timestamp: nil, collection_task_ids: [], new: true)
  end
end

And(/^I set all "([^"]*)" documents to have the following$/) do |collection, table|
  new_doc_info = table.rows_hash
  new_doc_info.each{|k,v| new_doc_info[k] = eval(v)}

  MongoSupport.instance.get_mongo_documents(collection).each do |document|
    MongoSupport.instance.update_document(collection, document['_id'], new_doc_info)
  end
end

And(/^the archive path is clean$/) do
  FileUtils.rmtree ENV['ARMAGH_ARCHIVE_PATH']
end

And(/^the a file containing "([^"]*)" should be archived$/) do |content|
  has_content = false
  now = Time.now.utc
  archive_path = File.join(ENV['ARMAGH_ARCHIVE_PATH'], '%02d' % now.year, '%02d' % now.month, '%02d.0000' % now.day)
  Dir.glob(File.join(archive_path, '*')).each do |file|
    has_content = File.read(file).include? content
    break if has_content
  end
  assert_true(has_content, "No file containing #{content} was found in #{archive_path}")
end