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
require_relative '../../../helpers/coverage_helper'

require_relative '../../../../lib/armagh/document/base_document/content_cleanup'

require 'test/unit'
require 'mocha/test_unit'
require 'bson'
require 'facets/kernel/deep_copy'

class TestContentCleanup < Test::Unit::TestCase

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
      "#{Armagh::BaseDocument::ContentCleanup::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
      "bad#{Armagh::BaseDocument::ContentCleanup::DOT_REPLACEMENT}key" => 'dot',
      'array' => [
        'some string',
        'another dirty',
        {
          'inner' => 'inner',
          'ts' => Time.at(0).utc,
          'inary' => %w(howdy okay),
          "#{Armagh::BaseDocument::ContentCleanup::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
          "bad#{Armagh::BaseDocument::ContentCleanup::DOT_REPLACEMENT}key" => 'dot'
        }
      ],
      'hash' => {
        '1' => 'something',
        '2' => 'another',
        '3' => ['one', 2, ['three'], {'four' => 'eek'}],
        'ts' => Time.at(0).utc,
        "#{Armagh::BaseDocument::ContentCleanup::DOLLAR_REPLACEMENT}bad_key" => 'dollar',
        "bad#{Armagh::BaseDocument::ContentCleanup::DOT_REPLACEMENT}key" => 'dot'
      },
      ' key ' => 'string',
      'raw' => @raw
    }

  end

  def test_clean_image
    cleaned_content = Armagh::BaseDocument::ContentCleanup::clean_image(@content)
    assert_equal(@clean_content, cleaned_content)
  end


  def test_clean_image_empty
    cleaned_content = Armagh::BaseDocument::ContentCleanup.clean_image({})
    assert_equal({}, cleaned_content)
  end

  def test_restore_image
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
    cleaned_content = Armagh::BaseDocument::ContentCleanup.restore_image( @clean_content )
    assert_equal(expected, cleaned_content)
  end

  def test_restore_image_empty
    cleaned_content = Armagh::BaseDocument::ContentCleanup.restore_image( {})
    assert_equal({}, cleaned_content)
  end

  def test_fix_encoding
    test_string = 'howdy'.force_encoding( 'us-ascii' )
    assert_equal 'US-ASCII', test_string.encoding.name
    fixed_string = Armagh::BaseDocument::ContentCleanup.fix_encoding( 'utf-8', test_string )
    assert_equal 'howdy', fixed_string
    assert_equal 'UTF-8', fixed_string.encoding.name
  end

end
