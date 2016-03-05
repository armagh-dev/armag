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
require_relative '../../../lib/logging/global_logger'
require 'test/unit'
require 'mocha/test_unit'

class TestGlobalLogger < Test::Unit::TestCase

  def setup
    @test_io = StringIO.new
    mock_mongo
    @component_name = 'test_logger'
    @logger = Armagh::Logging::GlobalLogger.new(@component_name, @test_io)
    @logger.instance_variable_set('@logdev', @test_io) # Silence STDOUT
  end

  def mock_mongo
    @mock = mock('object')
    Armagh::Connection.stubs(:log).returns(@mock)
  end

  def mock_mongo_resource
    @mock_resource = mock('object')
    Armagh::Connection.stubs(:resource_log).returns(@mock_resource)
  end

  def test_add_block
    @logger.expects(:add_global).returns(nil)
    message = 'log message'
    @logger.add(Logger::DEBUG) { message }

    assert_includes(@test_io.string, 'DEBUG')
    assert_includes(@test_io.string, @component_name)
    assert_includes(@test_io.string, message)
    assert_includes(@test_io.string, Process.pid.to_s)
  end

  def test_add_progname
    @logger.expects(:add_global).returns(nil)
    message = 'log message'
    @logger.add(Logger::WARN, nil, message)

    assert_includes(@test_io.string, 'WARN')
    assert_includes(@test_io.string, @component_name)
    assert_includes(@test_io.string, message)
    assert_includes(@test_io.string, Process.pid.to_s)
  end

  def test_add_message
    @logger.expects(:add_global).returns(nil)
    message = 'message that is logged'
    @logger.add(Logger::INFO, message)

    assert_includes(@test_io.string, 'INFO')
    assert_includes(@test_io.string, @component_name)
    assert_includes(@test_io.string, message)
    assert_includes(@test_io.string, Process.pid.to_s)
  end

  def test_add_global
    message = 'test message'
    @mock.expects(:insert_one).with(
        all_of(
            has_entries({
                            'level' => 'ERROR',
                            'component' => @component_name,
                            'hostname' => Socket.gethostname,
                            'pid' => Process.pid,
                            'message' => message
                        })
        )
    )
    @logger.add_global(Logger::ERROR, message)
  end

  def test_add_global_resource_log
    @logger.is_a_resource_log = true
    mock_mongo_resource
    message = 'test message'
    @mock_resource.expects(:insert_one).with(
        all_of(
            has_entries({
                            'level' => 'ERROR',
                            'component' => @component_name,
                            'hostname' => Socket.gethostname,
                            'pid' => Process.pid,
                            'message' => message
                        })
        )
    )
    @logger.add_global(Logger::ERROR, message)
  end

  def test_add_global_exception
    exception_message = 'this is the exception'
    backtrace = %w(back trace)
    exception = StandardError.new(exception_message)
    exception.set_backtrace backtrace
    @mock.expects(:insert_one).with(
        all_of(
            has_entries({
                            'level' => 'INFO',
                            'component' => @component_name,
                            'hostname' => Socket.gethostname,
                            'pid' => Process.pid,
                            'exception' => {
                                'class' => exception.class,
                                'message' => exception.message,
                                'trace' => backtrace
                            }
                        })
        )
    )
    @logger.add_global(Logger::INFO, exception)
  end

  def test_add_global_exception_nested
    exception = StandardError.new('Exception')
    backtrace = %w(one two)
    exception_middle = NameError.new('Exception middle')
    backtrace_middle = %w(three four)
    exception_root = EncodingError.new('Exception root')
    backtrace_root = %w(five six)

    expected = {
        'level' => 'INFO',
        'component' => @component_name,
        'hostname' => Socket.gethostname,
        'pid' => Process.pid,
        'exception' => {
            'class' => exception.class,
            'message' => exception.message,
            'trace' => backtrace,
            'cause' => {
                'class' => exception_middle.class,
                'message' => exception_middle.message,
                'trace' => backtrace_middle,
                'cause' => {
                    'class' => exception_root.class,
                    'message' => exception_root.message,
                    'trace' => backtrace_root,
                }
            }
        }
    }

    @mock.expects(:insert_one).with(all_of(has_entries(expected)))

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
      @logger.add_global(Logger::INFO, e)
    end

  end
end
