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

require_relative '../test_helpers/coverage_helper'
require_relative '../../lib/logging/global_logger'
require 'test/unit'
require 'mocha/test_unit'

class TestMongoConnection < Test::Unit::TestCase

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

  def test_add_block
    @logger.expects(:add_global).returns(nil)
    message = 'log message'
    @logger.add(Logger::DEBUG) {message}

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

  def test_add_global_exception
    exception_message = 'this is the exception'
    backtrace = ['back', 'trace']
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
                                'message' => exception.inspect,
                                'trace' => backtrace
                            }
                        })
        )
    )
    @logger.add_global(Logger::INFO, exception)
  end
end
