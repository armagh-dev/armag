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
require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/document/document'
require_relative '../../../lib/utils/document_helper'

require 'test/unit'
require 'mocha/test_unit'

class TestDocumentHelper < Test::Unit::TestCase

  def setup
    @content = {
      'string' => 'this is some string',
      'dirty' => "\n  this is some dirty\n string\n ",
      'ts' => Time.at(0).utc,
      'array' => [
        'some string',
        '   another dirty ',
        {
          'inner' => '   inner   ',
          'ts' => Time.at(0).utc,
          'inary' => ['  howdy', 'okay']
        }
      ],
      'hash' => {
        '1' => '   something     ',
        '2' => 'another',
        '3' => ['  one', 2, ['three '], {'four' => ' eek '}],
        'ts' => Time.at(0).utc
      },
      ' key ' => 'string'
    }

    @metadata = {
      'something' => [
        '  inside  '
      ]
    }
    @doc = mock('document')

    Armagh::Document.any_instance.stubs(:save)
    @doc = Armagh::Document.create(type: 'type',
                                   content: @content,
                                   metadata: @metadata,
                                   pending_actions: [],
                                   state: 'ready',
                                   document_id: '123  ',
                                   collection_task_ids: ['abc'],
                                   document_timestamp: Time.at(0).utc,
                                   title: '  some title  ',
                                   copyright: "copyright\n",
                                   display: '  display    '
    )


  end

  def test_clean_document
    expected = {
      'archive_file' =>nil,
      'collection_task_ids' =>['abc'],
      'copyright' => 'copyright',
      'created_timestamp' =>nil,
      'dev_errors' =>{},
      'display' => 'display',
      'document_id' => '123',
      'document_timestamp' =>Time.at(0).utc,
      'locked' =>false,
      'metadata' =>{'something' =>['inside']},
      'ops_errors' =>{},
      'pending_actions' =>[],
      'published_timestamp' =>nil,
      'source' =>{},
      'state' => 'ready',
      'title' => 'some title',
      'type' => 'type',
      'updated_timestamp' =>nil,

      'content' => {
        'string' => 'this is some string',
        'dirty' => "this is some dirty\n string",
        'ts' => Time.at(0).utc,
        'array' => [
          'some string',
          'another dirty',
          {
            'inner' => 'inner',
            'ts' => Time.at(0).utc,
            'inary' => %w(howdy okay)
          }
        ],
        'hash' => {
          '1' => 'something',
          '2' => 'another',
          '3' => ['one', 2, ['three'], {'four' => 'eek'}],
          'ts' => Time.at(0).utc
        },
        ' key ' => 'string'
      }
    }
    
    Armagh::Utils::DocumentHelper.clean_document(@doc)
    assert_equal(expected, @doc.db_doc)
  end


  def test_clean_document_empty
    @doc.db_doc.clear
    Armagh::Utils::DocumentHelper.clean_document(@doc)
    assert_equal({}, @doc.db_doc)
  end
end