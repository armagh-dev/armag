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
require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/utils/exception_helper'

require 'test/unit'
require 'mocha/test_unit'

class TestExceptionHelper < Test::Unit::TestCase

  def setup
  end

  def test_exception_to_hash
    exception_message = 'this is the exception'
    backtrace = %w(back trace)
    exception = StandardError.new(exception_message)
    exception.set_backtrace(backtrace)

    expected = {
        'class' => 'StandardError',
        'message' => exception_message,
        'trace' => backtrace
    }

    actual = Armagh::Utils::ExceptionHelper.exception_to_hash(exception)
    assert_in_delta(Time.now, actual['timestamp'], 1)
    actual.delete('timestamp')
    assert_equal(expected, actual)
  end

  def test_exception_to_hash_nested
    executed = false
    exception = StandardError.new('Exception')
    backtrace = %w(one two)
    exception_middle = NameError.new('Exception middle')
    backtrace_middle = %w(three four)
    exception_root = EncodingError.new('Exception root')
    backtrace_root = %w(five six)

    expected = {
        'class' => exception.class.name,
        'message' => exception.message,
        'trace' => backtrace,
        'cause' => {
            'class' => exception_middle.class.name,
            'message' => exception_middle.message,
            'trace' => backtrace_middle,
            'cause' => {
                'class' => exception_root.class.name,
                'message' => exception_root.message,
                'trace' => backtrace_root,
            }
        }
    }

    begin
      begin
        begin
          raise exception_root
        rescue => e
          e.set_backtrace backtrace_root
          raise exception_middle
        end
      rescue => e
        e.set_backtrace backtrace_middle
        raise exception
      end
    rescue => e
      e.set_backtrace backtrace

      actual = Armagh::Utils::ExceptionHelper.exception_to_hash(exception)
      assert_in_delta(Time.now, actual['timestamp'], 1)
      actual.delete('timestamp')
      assert_equal(expected, actual)

      executed = true
    end



    assert_true executed, 'Nested exception block never executed'
  end

  def test_exception_to_string
    exception_message = 'this is the exception'
    backtrace = %w(back trace)
    exception = StandardError.new(exception_message)
    exception.set_backtrace(backtrace)
    expected = "StandardError => this is the exception\n  back\n  trace"

    assert_equal(expected, Armagh::Utils::ExceptionHelper.exception_to_string(exception))
  end

  def test_exception_to_string_nested
    executed = false
    exception = StandardError.new('Exception')
    backtrace = %w(one two)
    exception_middle = NameError.new('Exception middle')
    backtrace_middle = %w(three four)
    exception_root = EncodingError.new('Exception root')
    backtrace_root = %w(five six)

    expected = "StandardError => Exception\n  one\n  two\nCaused By: NameError => Exception middle\n  three\n  four\nCaused By: EncodingError => Exception root\n  five\n  six"

    begin
      begin
        begin
          raise exception_root
        rescue => e
          e.set_backtrace backtrace_root
          raise exception_middle
        end
      rescue => e
        e.set_backtrace backtrace_middle
        raise exception
      end
    rescue => e
      e.set_backtrace backtrace
      assert_equal(expected, Armagh::Utils::ExceptionHelper.exception_to_string(e))
      executed = true
    end

    assert_true executed, 'Nested exception block never executed'
  end

end