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

require_relative '../../../lib/environment.rb'

require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/logging'

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

end