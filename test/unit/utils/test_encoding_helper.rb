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

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/utils/encoding_helper'

require 'test/unit'
require 'mocha/test_unit'

require 'bson'

class TestEncodingHelper < Test::Unit::TestCase

  def setup
    @logger = mock('logger')
  end

  def test_encode_string
    str = "\xAE"
    str.force_encoding(Encoding::UTF_8) # Start as invalid utf-8

    assert_false str.valid_encoding?
    str = Armagh::Utils::EncodingHelper.fix_encoding(str, logger: @logger)
    assert_true str.valid_encoding?
  end

  def test_encode_frozen_string
    internal = Encoding.default_internal
    Encoding.default_internal = Encoding::UTF_8
    str = "\xAE"
    str.freeze
    Encoding.default_internal = internal

    assert_true str.frozen?
    assert_false str.valid_encoding?
    str = Armagh::Utils::EncodingHelper.fix_encoding(str, logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_complex_hash
    internal = Encoding.default_internal
    Encoding.default_internal = Encoding::UTF_8

    hash = {
        'array' => ["\xAE"],
        'frozen_array' => ["\xAE"].freeze,
        'frozen_array_elements' => ["\xAE".freeze].freeze,

        'hash' => {
            'array' => ["\xAE"],
            'frozen_array' => ["\xAE"].freeze,
            'frozen_array_elements' => ["\xAE".freeze].freeze,
            'string' => "\xAE",
            'frozen_string' => "\xAE".freeze
        },

        'string' => "\xAE",
        'frozen_string' => "\xAE".freeze,

        'frozen_hash' => {
            'array' => ["\xAE"],
            'frozen_array' => ["\xAE"].freeze,
            'frozen_array_elements' => ["\xAE".freeze].freeze,
            'string' => "\xAE",
            'frozen_string' => "\xAE".freeze
        },
    }

    Encoding.default_internal = internal

    assert_false hash['array'].first.valid_encoding?
    assert_false hash['frozen_array'].first.valid_encoding?
    assert_false hash['frozen_array_elements'].first.valid_encoding?

    assert_false hash['hash']['array'].first.valid_encoding?
    assert_false hash['hash']['frozen_array'].first.valid_encoding?
    assert_false hash['hash']['frozen_array_elements'].first.valid_encoding?
    assert_false hash['hash']['string'].valid_encoding?
    assert_false hash['hash']['frozen_string'].valid_encoding?

    assert_false hash['frozen_hash']['array'].first.valid_encoding?
    assert_false hash['frozen_hash']['frozen_array'].first.valid_encoding?
    assert_false hash['frozen_hash']['frozen_array_elements'].first.valid_encoding?
    assert_false hash['frozen_hash']['string'].valid_encoding?
    assert_false hash['frozen_hash']['frozen_string'].valid_encoding?

    assert_false hash['string'].valid_encoding?
    assert_false hash['frozen_string'].valid_encoding?

    hash = Armagh::Utils::EncodingHelper.fix_encoding(hash, logger: @logger)

    assert_true hash['array'].first.valid_encoding?
    assert_true hash['frozen_array'].first.valid_encoding?
    assert_true hash['frozen_array_elements'].first.valid_encoding?

    assert_true hash['hash']['array'].first.valid_encoding?
    assert_true hash['hash']['frozen_array'].first.valid_encoding?
    assert_true hash['hash']['frozen_array_elements'].first.valid_encoding?
    assert_true hash['hash']['string'].valid_encoding?
    assert_true hash['hash']['frozen_string'].valid_encoding?

    assert_true hash['string'].valid_encoding?
    assert_true hash['frozen_string'].valid_encoding?
  end

  def test_string_target
    str = 'I am a valid string'
    str.force_encoding(Encoding::UTF_8)
    str = Armagh::Utils::EncodingHelper.fix_encoding(str, logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_fix_proposed
    str = 'I am a valid string'
    str.force_encoding(Encoding::BINARY)
    str = Armagh::Utils::EncodingHelper.fix_encoding(str, proposed_encoding: Encoding::BINARY, logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_bad_proposed
    @logger.expects(:ops_warn)

    str = 'I am a valid string'
    str.force_encoding(Encoding::BINARY)
    str = Armagh::Utils::EncodingHelper.fix_encoding(str, proposed_encoding: 'invalid encoding', logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_no_valid_encoding
    @logger.expects(:ops_warn)

    str = 'Evil String'
    str.stubs(valid_encoding?: false)
    str.force_encoding(Encoding::BINARY)

    str = Armagh::Utils::EncodingHelper.fix_encoding(str, logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_broken_encoding
    Armagh::Logging.expects(:ops_error_exception)

    str = 'Evil String'
    str.expects(:encoding).raises(RuntimeError.new)
    str.force_encoding(Encoding::BINARY)

    str = Armagh::Utils::EncodingHelper.fix_encoding(str, logger: @logger)
    assert_true str.valid_encoding?
    assert_equal(Encoding::UTF_8, str.encoding)
  end

  def test_bad_env_encoding
    initial_encoding = ENV['ARMAGH_ENCODING']
    ENV['ARMAGH_ENCODING'] = 'invalid encoding'
    assert_raise(Armagh::Errors::EncodingError){Armagh::Utils::EncodingHelper.send(:get_target_encoding)}
  ensure
    if initial_encoding
      ENV['ARMAGH_ENCODING'] = initial_encoding
    else
      ENV.delete('ARMAGH_ENCODING')
    end
  end

  def test_benchmark
    iso_8859_4_str = "\x00 \x01 \x02 \x03 \x04 \x05 \x06 \x07 \x08 \x09 \x0A \x0B \x0C \x0D \x0E \x0F \x10 \x11 \x12 \x13 \x14 \x15 \x16 \x17 \x18 \x19 \x1A \x1B \x1C \x1D \x1E \x1F \x20 \x21 \x22 \x23 \x24 \x25 \x26 \x27 \x28 \x29 \x2A \x2B \x2C \x2D \x2E \x2F \x30 \x31 \x32 \x33 \x34 \x35 \x36 \x37 \x38 \x39 \x3A \x3B \x3C \x3D \x3E \x3F \x40 \x41 \x42 \x43 \x44 \x45 \x46 \x47 \x48 \x49 \x4A \x4B \x4C \x4D \x4E \x4F \x50 \x51 \x52 \x53 \x54 \x55 \x56 \x57 \x58 \x59 \x5A \x5B \x5C \x5D \x5E \x5F \x60 \x61 \x62 \x63 \x64 \x65 \x66 \x67 \x68 \x69 \x6A \x6B \x6C \x6D \x6E \x6F \x70 \x71 \x72 \x73 \x74 \x75 \x76 \x77 \x78 \x79 \x7A \x7B \x7C \x7D \x7E \x7F \x80 \x81 \x82 \x83 \x84 \x85 \x86 \x87 \x88 \x89 \x8A \x8B \x8C \x8D \x8E \x8F \x90 \x91 \x92 \x93 \x94 \x95 \x96 \x97 \x98 \x99 \x9A \x9B \x9C \x9D \x9E \x9F \xA0 \xA4 \xA7 \xA8 \xAD \xAF \xB0 \xB4 \xB8 \xC1 \xC2 \xC3 \xC4 \xC5 \xC6 \xC9 \xCB \xCD \xCE \xD4 \xD5 \xD6 \xD7 \xD8 \xDA \xDB \xDC \xDF \xE1 \xE2 \xE3 \xE4 \xE5 \xE6 \xE9 \xEB \xED \xEE \xF4 \xF5 \xF6 \xF7 \xF8 \xFA \xFB \xFC \xC0 \xE0 \xA1 \xB1 \xC8 \xE8 \xD0 \xF0 \xAA \xBA \xCC \xEC \xCA \xEA \xAB \xBB \xA5 \xB5 \xCF \xEF \xC7 \xE7 \xD3 \xF3 \xA2 \xA6 \xB6 \xD1 \xF1 \xBD \xBF \xD2 \xF2 \xA3 \xB3 \xA9 \xB9 \xAC \xBC \xDD \xFD \xDE \xFE \xD9 \xF9 \xAE \xBE \xB7 \xFF \xB2 "

    assert_equal(Encoding::UTF_8, iso_8859_4_str.encoding)
    assert_false iso_8859_4_str.valid_encoding?

    metadata = {}
    10.times do |i|
      metadata["field_#{i}"] = iso_8859_4_str.dup
    end

    content = {}
    100.times do |i|
      content["field_#{i}"] = iso_8859_4_str.dup
    end

    hash = {
        'metadata' => metadata,
        'content' => content
    }

    assert_false hash['content']['field_0'].valid_encoding?

    start = Time.now
    hash = Armagh::Utils::EncodingHelper.fix_encoding(hash, logger: @logger)
    elapsed = Time.now - start
    assert_true elapsed < 0.1, "fix_encoding took longer than 0.1 seconds to execute (note: this did not execute the ideal case).  Consider evaluating the performance.  It took #{elapsed} seconds."

    assert_true hash['content']['field_0'].valid_encoding?
  end

  def test_benchmark_best
    lorem = 'Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. Aenean massa. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem. Nulla consequat massa quis enim. Donec pede justo, fringilla vel, aliquet nec, vulputate eget, arcu. In enim justo, rhoncus ut, imperdiet a, venenatis vitae, justo. Nullam dictum felis eu pede mollis pretium. Integer tincidunt. Cras dapibus. Vivamus elementum semper nisi. Aenean vulputate eleifend tellus. Aenean leo ligula, porttitor eu, consequat vitae, eleifend ac, enim. Aliquam lorem ante, dapibus in, viverra quis, feugiat a, tellus. Phasellus viverra nulla ut metus varius laoreet. Quisque rutrum. Aenean imperdiet. Etiam ultricies nisi vel augue. Curabitur ullamcorper ultricies nisi. Nam eget dui. Etiam rhoncus. Maecenas tempus, tellus eget condimentum rhoncus, sem quam semper libero, sit amet adipiscing sem neque sed ipsum. Nam quam nunc, blandit vel, luctus pulvinar, hendrerit id, lorem. Maecenas nec odio et ante tincidunt tempus. Donec vitae sapien ut libero venenatis faucibus. Nullam quis ante. Etiam sit amet orci eget eros faucibus tincidunt. Duis leo. Sed fringilla mauris sit amet nibh. Donec sodales sagittis magna. Sed consequat, leo eget bibendum sodales, augue velit cursus nunc,'
    assert_equal(Encoding::UTF_8, lorem.encoding)
    assert_true lorem.valid_encoding?

    metadata = {}
    10.times do |i|
      metadata["field_#{i}"] = lorem.dup
    end

    content = {}
    100.times do |i|
      content["field_#{i}"] = lorem.dup
    end

    hash = {
        'metadata' => metadata,
        'content' => content
    }

    assert_true hash['content']['field_0'].valid_encoding?

    start = Time.now
    hash = Armagh::Utils::EncodingHelper.fix_encoding(hash, logger: @logger)
    elapsed = Time.now - start
    assert_true elapsed < 0.001, "fix_encoding took longer than 0.001 seconds to execute the ideal case.  Consider evaluating the performance.  It took #{elapsed} seconds."
    assert_true hash['content']['field_0'].valid_encoding?
  end

  def test_doc
    timestamp = Time.now
    binary = BSON::Binary.new('Some BSON Binary Content')

    doc = {
        'content' => {
            'bson_binary' => binary,
            'text' => 'text'
        },
        'metadata' => {
            'timestamp' => timestamp,
            'text' => 'text'
        }
    }

    expected_doc = {
        'content' => {
            'bson_binary' => binary,
            'text' => 'text'
        },
        'metadata' => {
            'timestamp' => timestamp,
            'text' => 'text'
        }
    }

    doc = Armagh::Utils::EncodingHelper.fix_encoding(doc, logger: @logger)

    assert_equal expected_doc, doc
  end
end