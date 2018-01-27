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
require_relative '../../helpers/coverage_helper'
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/logging'

require 'test/unit'
require 'mocha/test_unit'

require 'socket'

class TestMongoAppender < Test::Unit::TestCase
  def setup
    @collection = mock('collection')
    @collection.stubs(:insert_one)
    Armagh::Connection.stubs(:resource_log).returns(@collection)
    Armagh::Connection.stubs(:log).returns(@collection)
    @mongo_appender = Armagh::Logging.mongo('appender')
    @event = ::Logging::LogEvent.new('logger_name', Armagh::Logging::ANY, nil, false )
    @hostname = Socket.gethostname
    Armagh::Logging.clear_details
  end

  def expect_message(expected)
    @collection.expects(:insert_one).with do |arg|
      ts = arg['timestamp']
      arg.delete('timestamp')
      assert_equal(expected, arg)
      assert_in_delta(Time.now, ts, 1)
      true
    end
  end

  def test_write_enhanced_exception
    expected = {
      'component' => 'logger_name',
      'hostname' => @hostname,
      'pid' => $PID,
      'level' => 'ANY',
      'message' => 'Details',
      'exception' => {
        'class' => RuntimeError.to_s,
        'message' => 'Howdy',
        'trace' => %w(some back trace)
      }
    }

    e = RuntimeError.new 'Howdy'
    e.set_backtrace(%w(some back trace))
    ee = Armagh::Logging::EnhancedException.new('Details', e)
    expect_message(expected)
    @event.data = ee
    @mongo_appender.write(@event)
  end

  def test_write_exception
    expected = {
      'component' => 'logger_name',
      'hostname' => @hostname,
      'pid' => $PID,
      'level' => 'ANY',
      'exception' => {
        'class' => RuntimeError.to_s,
        'message' => 'Howdy',
        'trace' => %w(some back trace)
      }
    }

    e = RuntimeError.new 'Howdy'
    e.set_backtrace(%w(some back trace))
    expect_message(expected)
    @event.data = e
    @mongo_appender.write(@event)
  end

  def test_write_message
    expected = {
      'component' => 'logger_name',
      'hostname' => @hostname,
      'pid' => $PID,
      'level' => 'ANY',
      'message' => 'test'
    }

    expect_message(expected)
    @event.data = 'test'
    @mongo_appender.write(@event)
  end

  def test_write_log
    Armagh::Connection.expects(:log).returns(@collection)
    Armagh::Connection.expects(:resource_log).never
    @mongo_appender.write(@event)
  end

  def test_write_resource_log
    @mongo_appender = Armagh::Logging.mongo('appender', 'resource_log' => true)
    Armagh::Connection.expects(:resource_log).returns(@collection)
    Armagh::Connection.expects(:log).never
    @mongo_appender.write(@event)
  end

  def test_write_error
    old_stderr = $stderr
    e = RuntimeError.new('kaboom')
    e.set_backtrace(%w(some back trace))
    Armagh::Connection.expects(:log).raises(e)
    $stderr = StringIO.new
    @mongo_appender.write(@event)
    assert_equal("#{e.inspect}\n#{e.backtrace.join("\n\t")}", $stderr.string.strip)
  ensure
    $stderr = old_stderr
  end

  def test_write_action_details
    mdc = {
      'workflow' => 'workflow_name',
      'action' => 'action_name',
      'action_supertype' => 'action_supertype_name'
    }
    ::Logging.stubs(:mdc).returns(mdc)
    expected = {
      'component' => 'logger_name',
      'hostname' => @hostname,
      'pid' => $PID,
      'level' => 'ANY',
      'message' => 'test',
      'workflow' => 'workflow_name',
      'action' => 'action_name',
      'action_supertype' => 'action_supertype_name'
    }

    expect_message(expected)
    @event.data = 'test'
    @mongo_appender.write(@event)
  end
end
