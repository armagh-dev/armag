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

require_relative '../../../lib/logging/hash_formatter'
require_relative '../../helpers/mock_logger'

require 'log4r'
require 'test/unit'
require 'mocha/test_unit'

class TestHashFormatter < Test::Unit::TestCase
  include ArmaghTest

  def setup
    mock_logger
    @hash_formatter = Log4r::HashFormatter.new
  end

  def test_format_string
    event = stub(name: 'item', level: Log4r::DEBUG, data: 'log message', tracer: ['one', 'two'])

    expected = {
        'component' => 'item',
        'hostname' => Socket.gethostname,
        'level' => 'DEBUG',
        'message' => 'log message',
        'trace' => ['one', 'two'],
        'pid' => $$
    }

    result = @hash_formatter.format(event)
    assert_in_delta(Time.now, result['timestamp'], 1)
    result.delete('timestamp')
    assert_equal(expected, result)
  end

  def test_format_object
    event = stub(name: 'item', level: Log4r::INFO, data: [1, 2, 3, 4, 5], tracer: ['one', 'two'])

    expected = {
        'component' => 'item',
        'hostname' => Socket.gethostname,
        'level' => 'INFO',
        'message' => '[1, 2, 3, 4, 5]',
        'trace' => ['one', 'two'],
        'pid' => $$
    }

    result = @hash_formatter.format(event)
    assert_in_delta(Time.now, result['timestamp'], 1)
    result.delete('timestamp')
    assert_equal(expected, result)
  end

  def test_format_enhanced_exception
    e = RuntimeError.new 'Failed!'
    ee = Armagh::Logging::EnhancedException.new('details', e)
    event = stub(name: 'item', level: Log4r::WARN, data: ee, tracer: ['one', 'two'])

    expected = {
        'component' => 'item',
        'hostname' => Socket.gethostname,
        'level' => 'WARN',
        'message' => 'details',
        'exception' => {
            'class' => 'RuntimeError',
            'message' => 'Failed!',
            'trace' => nil
        },
        'trace' => ['one', 'two'],
        'pid' => $$
    }

    result = @hash_formatter.format(event)
    assert_in_delta(Time.now, result['timestamp'], 1)
    result.delete('timestamp')
    assert_equal(expected, result)
  end

  def test_format_exception
    e = RuntimeError.new 'Failed!'
    event = stub(name: 'item', level: Log4r::WARN, data: e, tracer: ['one', 'two'])

    expected = {
        'component' => 'item',
        'hostname' => Socket.gethostname,
        'level' => 'WARN',
        'exception' => {
            'class' => 'RuntimeError',
            'message' => 'Failed!',
            'trace' => nil
        },
        'trace' => ['one', 'two'],
        'pid' => $$
    }

    result = @hash_formatter.format(event)
    assert_in_delta(Time.now, result['timestamp'], 1)
    result.delete('timestamp')
    assert_equal(expected, result)
  end

  def test_format_nested_exceptions
    exception = nil

    begin
      begin
        begin
          raise 'Inside'
        rescue
          raise 'Middle'
        end
      rescue
        raise 'Outside'
      end
    rescue => e
      exception = e
    end

    assert_not_nil exception
    event = stub(name: 'item', level: Log4r::WARN, data: exception, tracer: nil)

    expected = {
        'component' => 'item',
        'hostname' => Socket.gethostname,
        'level' => 'WARN',
        'exception' => {
            'class' => 'RuntimeError',
            'message' => 'Outside',
            'trace' => nil,
            'cause' => {
                'class' => 'RuntimeError',
                'message' => 'Middle',
                'trace' => nil,
                'cause' => {
                    'class' => 'RuntimeError',
                    'message' => 'Inside',
                    'trace' => nil,
                }
            }
        },
        'pid' => $$
    }

    result = @hash_formatter.format(event)
    assert_in_delta(Time.now, result['timestamp'], 1)
    result.delete('timestamp')

    assert_not_empty(result['exception']['trace'])
    result['exception']['trace'] = nil
    assert_not_empty(result['exception']['cause']['trace'])
    result['exception']['cause']['trace'] = nil
    assert_not_empty(result['exception']['cause']['cause']['trace'])
    result['exception']['cause']['cause']['trace'] = nil

    assert_equal(expected, result)
  end


end