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
require_relative '../../helpers/coverage_helper'
require_relative '../../helpers/armagh_test'
require_relative '../../../lib/armagh/utils/db_doc_helper'
require_relative '../../../lib/armagh/connection/db_doc'

require 'test/unit'
require 'mocha/test_unit'
require 'bson'
require 'facets/kernel/deep_copy'

class TestDoc < Armagh::Connection::DBDoc
  def self.create(content)
    new(content)
  end
end

class TestDBDocHelper < Test::Unit::TestCase

  def setup
    @raw = BSON::Binary.new('raw data')
    @content = {
      'string' => 'this is some string',
      'dirty' => "\n  this is some dirty\n string\n ",
      'ts' => Time.at(0).utc,
      '$bad_key' => 'dollar',
      'bad.key' => 'dot',
      'nil' => nil,
      'array' => [
        'some string',
        '   another dirty ',
        {
          'inner' => '   inner   ',
          'ts' => Time.at(0).utc,
          'inary' => ['  howdy', 'okay'],
          '$bad_key' => 'dollar',
          'bad.key' => 'dot',
          'nil' => nil
        }
      ],
      'hash' => {
        '1' => '   something     ',
        '2' => 'another',
        '3' => ['  one', 2, ['three '], {'four' => ' eek '}],
        'ts' => Time.at(0).utc,
        '$bad_key' => 'dollar',
        'bad.key' => 'dot'
      },
      ' key ' => 'string',
      'raw' => @raw
    }

    @clean_content = {
      'string' => 'this is some string',
      'dirty' => "this is some dirty\n string",
      'ts' => Time.at(0).utc,
      "#{Armagh::Utils::DBDocHelper::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
      "bad#{Armagh::Utils::DBDocHelper::DOT_REPLACEMENT}key" => 'dot',
      'array' => [
        'some string',
        'another dirty',
        {
          'inner' => 'inner',
          'ts' => Time.at(0).utc,
          'inary' => %w(howdy okay),
          "#{Armagh::Utils::DBDocHelper::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
          "bad#{Armagh::Utils::DBDocHelper::DOT_REPLACEMENT}key" => 'dot'
        }
      ],
      'hash' => {
        '1' => 'something',
        '2' => 'another',
        '3' => ['one', 2, ['three'], {'four' => 'eek'}],
        'ts' => Time.at(0).utc,
        "#{Armagh::Utils::DBDocHelper::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
        "bad#{Armagh::Utils::DBDocHelper::DOT_REPLACEMENT}key" => 'dot'
      },
      ' key ' => 'string',
      'raw' => @raw
    }

    @doc = TestDoc.create(@content)
  end

  def test_clean_document
    Armagh::Utils::DBDocHelper.clean_model(@doc)
    assert_equal(@clean_content, @doc.db_doc)
  end


  def test_clean_document_empty
    @doc.db_doc.clear
    Armagh::Utils::DBDocHelper.clean_model(@doc)
    assert_equal({}, @doc.db_doc)
  end

  def test_restore_document
    expected = {
      'string' => 'this is some string',
      'dirty' => "this is some dirty\n string",
      'ts' => Time.at(0).utc,
      '$bad_key' => 'dollar',
      'bad.key' => 'dot',
      'array' => [
        'some string',
        'another dirty',
        {
          'inner' => 'inner',
          'ts' => Time.at(0).utc,
          'inary' => %w(howdy okay),
          '$bad_key' => 'dollar',
          'bad.key' => 'dot',
        }
      ],
      'hash' => {
        '1' => 'something',
        '2' => 'another',
        '3' => ['one', 2, ['three'], {'four' => 'eek'}],
        'ts' => Time.at(0).utc,
        '$bad_key' => 'dollar',
        'bad.key' => 'dot'
      },
      ' key ' => 'string',
      'raw' => @raw
    }
    doc = TestDoc.create(@clean_content)
    Armagh::Utils::DBDocHelper.restore_model doc
    assert_equal(expected, doc.db_doc)
  end

  def test_restore_document_empty
    @doc.db_doc.clear
    Armagh::Utils::DBDocHelper.restore_model @doc
    assert_equal({}, @doc.db_doc)
  end

  def test_restore_document_raw
    expected = {
      'string' => 'this is some string',
      'dirty' => "this is some dirty\n string",
      'ts' => Time.at(0).utc,
      '$bad_key' => 'dollar',
      'bad.key' => 'dot',
      'array' => [
        'some string',
        'another dirty',
        {
          'inner' => 'inner',
          'ts' => Time.at(0).utc,
          'inary' => %w(howdy okay),
          '$bad_key' => 'dollar',
          'bad.key' => 'dot',
        }
      ],
      'hash' => {
        '1' => 'something',
        '2' => 'another',
        '3' => ['one', 2, ['three'], {'four' => 'eek'}],
        'ts' => Time.at(0).utc,
        '$bad_key' => 'dollar',
        'bad.key' => 'dot'
      },
      ' key ' => 'string',
      'raw' => @raw
    }

    content = @clean_content.deep_copy
    Armagh::Utils::DBDocHelper.restore_model(content, raw: true)
    assert_equal(expected, content)
  end
end
