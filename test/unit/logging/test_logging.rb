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
    Armagh::Logging.clear_details
  end

  def has_mongo_outputter
    Armagh::Logging.loggers.each do |logger|
      logger.appenders.each do |a|
        return true if a.is_a? Armagh::Logging::MongoAppender
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
    assert_kind_of(::Logging::Logger, logger)
    assert_same(logger, Armagh::Logging.set_logger('test_logger'))
    assert_not_same(logger, Armagh::Logging.set_logger('test_logger2'))
  end

  def test_set_and_clear_details
    workflow = 'workflow_name'
    action = 'action_name'
    action_supertype = 'supertype_name'

    assert_nil ::Logging.mdc['workflow']
    assert_nil ::Logging.mdc['action']
    assert_nil ::Logging.mdc['action_supertype']
    assert_nil ::Logging.mdc['action_workflow']

    Armagh::Logging.set_details(workflow, action, action_supertype)

    assert_equal workflow, ::Logging.mdc['workflow']
    assert_equal action, ::Logging.mdc['action']
    assert_equal action_supertype, ::Logging.mdc['action_supertype']
    assert_equal " [#{workflow}/#{action}]", ::Logging.mdc['action_workflow']

    Armagh::Logging.clear_details

    assert_nil ::Logging.mdc['workflow']
    assert_nil ::Logging.mdc['action']
    assert_nil ::Logging.mdc['action_supertype']
    assert_nil ::Logging.mdc['action_workflow']
  end

  def test_default_log_level
    logger = mock
    logger.expects(:name).returns('test_logger')
    logger.expects(:level).returns(Armagh::Logging::WARN)
    Armagh::Logging.expects(:set_logger).returns(logger)
    assert_equal(Armagh::Logging::LEVELS[Armagh::Logging::WARN], Armagh::Logging.default_log_level(logger))
  end

  def test_set_level
    logger = Armagh::Logging.set_logger('test_logger')
    logger.clear_appenders
    logger.additive = false
    assert_not_equal(Armagh::Logging::INFO, logger.level)
    Armagh::Logging.set_level(logger, 'INFO')
    assert_equal(Armagh::Logging::INFO, logger.level)
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