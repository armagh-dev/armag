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

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/logging'

require 'tmpdir'
require 'fileutils'

require 'test/unit'
require 'mocha/test_unit'

class TestLogging < Test::Unit::TestCase

  def setup
    @dir = Dir.mktmpdir
    @log_dir = File.join(@dir, 'log')
    ENV[ 'ARMAGH_APP_LOG' ] = @log_dir
    @stderr = $stderr
  end

  def teardown
    $stderr = @stderr
    FileUtils.rm_rf @dir
  end

  def has_mongo_outputter
    Log4r::Logger.each_logger do |logger|
      logger.outputters.each do |outputter|
        return true if outputter.is_a? Log4r::MongoOutputter
      end
    end
    false
  end

  def test_init_new_dir
    assert_false File.directory? @log_dir
    Armagh::Logging.init_log_env
    assert_true File.directory? @log_dir
  end

  def test_init_existing_dir
    FileUtils.mkdir_p @log_dir
    FileUtils.stubs(:mkdir_p).never
    assert_true File.directory? @log_dir
    Armagh::Logging.init_log_env
    assert_true File.directory? @log_dir
  end

  def test_init_cant_create
    assert_false File.directory? @log_dir
    FileUtils.stubs(:mkdir_p).raises(Errno::EACCES.new('Permission denied'))

    stderr = StringIO.new
    $stderr = stderr
    e = assert_raise(SystemExit) {Armagh::Logging.init_log_env}
    assert_equal 1, e.status
    error_msg = stderr.string.gsub(/'.*'/,"'placeholder'").strip
    assert_equal "Log directory 'placeholder' does not exist and could not be created.  Please create the directory and grant the user running armagh full permissions.", error_msg
    assert_false File.directory? @log_dir
  end

  def test_ops_error_exception
    logger = mock
    exception = nil

    begin
      raise 'Error'
    rescue => e
      exception = e
    end

    logger.expects(:ops_error).with do |error|
      assert_equal exception, error.exception
      assert_equal 'Something bad happened.', error.additional_details
      true
    end

    Armagh::Logging.ops_error_exception(logger, exception, 'Something bad happened.')
  end

  def test_dev_error_exception
    logger = mock
    exception = nil

    begin
      raise 'Error'
    rescue => e
      exception = e
    end

    logger.expects(:dev_error).with do |error|
      assert_equal exception, error.exception
      assert_equal 'Something bad happened.', error.additional_details
      true
    end

    Armagh::Logging.dev_error_exception(logger, exception, 'Something bad happened.')
  end

  def test_set_logger
    logger = Armagh::Logging.set_logger('test_logger')
    assert_kind_of(Log4r::Logger, logger)
    assert_same(logger, Armagh::Logging.set_logger('test_logger'))
    assert_not_same(logger, Armagh::Logging.set_logger('test_logger2'))
  end

  def test_default_log_level
    logger = mock
    logger.expects(:name).returns('test_logger')
    logger.expects(:level).returns(2)
    logger.expects(:levels).returns(%w(error warn info))
    Armagh::Logging.expects(:set_logger).returns(logger)
    assert_equal('info', Armagh::Logging.default_log_level(logger))
  end

  def test_set_level
    logger = Armagh::Logging.set_logger('test_logger')
    assert_not_equal(2, logger.level)
    Armagh::Logging.set_level(logger, 'info')
    assert_equal(2, logger.level)
  end

  def test_valid_log_levels
    levels =  Armagh::Logging.valid_log_levels
    assert_include(levels, 'debug')
    assert_include(levels, 'info')
    assert_include(levels, 'warn')
    assert_include(levels, 'error')
  end

  def test_valid_level?
    assert_true Armagh::Logging.valid_level?('debug')
    assert_true Armagh::Logging.valid_level?('info')
    assert_true Armagh::Logging.valid_level?('warn')
    assert_false Armagh::Logging.valid_level?('bananas')
  end

  def test_disable_mongo
    assert_true has_mongo_outputter
    Armagh::Logging.disable_mongo_log
    assert_false has_mongo_outputter
  end

end