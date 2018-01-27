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

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/configuration/file_based_configuration.rb'
require 'test/unit'
require 'mocha/test_unit'
require 'fakefs/safe'
require 'tempfile'

class TestFileBasedConfiguration < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    @logger = mock
    @logger.stubs(:error)
    @expected_config = {'test_key' => {'field_1' => 1, 'field_2' => 2}}
    mock_oj_load @expected_config
  end

  def mock_oj_load(result)
    Oj.stubs(:load).returns result
  end

  def test_filepath_env
    file = Tempfile.new('file')
    path = file.path
    tmp = ENV['ARMAGH_CONFIG_FILE']
    ENV['ARMAGH_CONFIG_FILE'] = path
    assert_equal(path, FileBasedConfiguration.filepath)
  ensure
    ENV['ARMAGH_CONFIG_FILE'] = tmp
    file.unlink
  end

  def test_filepath_default
    tmp = ENV['ARMAGH_CONFIG_FILE']
    ENV['ARMAGH_CONFIG_FILE'] = nil

    path = FileBasedConfiguration.filepath
    assert_true File.exists? path
    default_config_path = File.absolute_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'armagh', 'armagh_env.json'))
    assert_equal(default_config_path, path)
  ensure
    ENV['ARMAGH_CONFIG_FILE'] = tmp
  end

  def test_filepath_etc
    FakeFS do
      FileUtils.mkdir_p File.join('/', 'etc','armagh')
      FileUtils.touch File.join('/', 'etc','armagh', 'armagh_env.json')
      path = FileBasedConfiguration.filepath
      assert_true File.exists? path
      assert_equal(File.join('/', 'etc','armagh', 'armagh_env.json'), path)
    end
  end

  def test_filepath_doesnt_exist
    File.stubs(:file?).returns false
    e = assert_raise(Armagh::Configuration::ConfigurationError) {FileBasedConfiguration.filepath}
    assert_equal "Can't find the armagh_env.json file in #{FileBasedConfiguration::CONFIG_DIRS.join(', ')}", e.message
  end

  def test_load_default
    mock_oj_load @expected_config
    config =  FileBasedConfiguration.load('test_key')
    assert_not_nil config
    assert_equal(@expected_config['test_key'], config)
  end

  def test_load_bad_key
    e = assert_raise(Armagh::Configuration::ConfigurationError) {FileBasedConfiguration.load('INVALID')}
    assert_equal "Configuration file #{FileBasedConfiguration.filepath} does not contain 'INVALID'.", e.message
  end

  def test_load_bad_config
    Oj.stubs(:load).raises(RuntimeError.new)
    e = assert_raise(Armagh::Configuration::ConfigurationError) {FileBasedConfiguration.load('INVALID')}
    assert_equal "Configuration file #{FileBasedConfiguration.filepath} could not be parsed.", e.message
  end
end
