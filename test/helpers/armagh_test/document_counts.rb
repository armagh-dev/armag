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

require_relative '../armagh_test'
require_relative '../../../lib/armagh/document/document'

require 'test/unit'
require 'mocha/test_unit'

module ArmaghTest
  def expect_document_counts( count_hashes )

    documents_in_process, failed_documents = count_hashes.partition{ |h| h['category'] == 'in process'}
    working_documents_in_process, published_documents_in_process = documents_in_process.partition{ |h| h['published_collection'].nil? }
    working_failed_documents, published_failed_documents = failed_documents.partition{ |h| h['published_collection'].nil? }

    published_collections = count_hashes.collect{ |h| h['published_collection']}.compact.sort.uniq

    @documents_mock ||= mock
    @documents_mock.stubs( name: 'documents' )
    @failures_mock ||= mock
    @failures_mock.stubs( name: 'failures' )
    Armagh::Connection.stubs( documents: @documents_mock, failures: @failures_mock )
    @published_mock = {}
    published_collections.each do |pc|
      @published_mock[pc] ||= mock
      @published_mock[pc].stubs( name: "documents.#{pc}")
      Armagh::Connection.stubs( :documents).with( pc ).returns( @published_mock[ pc ])
    end

    Armagh::Connection.stubs( all_published_collections: @published_mock.values )

    working_documents_in_process_db_result = db_result_for(working_documents_in_process)
    published_documents_in_process_db_result = db_result_for(published_documents_in_process).group_by{ |result| result['_id'][ 'type' ]}
    working_failed_documents_db_result = db_result_for(working_failed_documents)
    published_failed_documents_db_result = db_result_for(published_failed_documents).group_by{ |result| result['_id'][ 'type']}

    count_by_doctype_stage = {'$group'=>{'_id'=>{'type'=>'$type','state'=>'$state'},'count'=>{'$sum'=>1}}}
    @documents_mock.expects(:aggregate).once.with( [count_by_doctype_stage] ).returns( working_documents_in_process_db_result)
    @failures_mock.expects(:aggregate).once.with( [count_by_doctype_stage] ).returns( working_failed_documents_db_result)
    published_collections.each do |pc|
      @published_mock[pc].expects(:aggregate).once.with( [ {'$match' =>  { 'pending_work' => true, '_locked' => false }}, count_by_doctype_stage]).returns( published_documents_in_process_db_result[pc])
    end
  end

  def db_result_for( count_hashes )
    count_hashes.collect do |hash|
      type, state = hash['docspec_string'].split(':')
      { '_id' => { 'type' => type, 'state' => state }, 'count' => hash['count']}
    end
  end
end

