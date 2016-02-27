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
require_relative '../test_helpers/mock_global_logger'
require_relative '../../../lib/configuration/file_based_configuration.rb'
require 'test/unit'
require 'mocha/test_unit'

class TestFileBasedConfiguration < Test::Unit::TestCase

  include Armagh::Configuration

  def setup
    @logger = mock
    @logger.stubs(:error)
  end

  def test_filepath
    pend
    assert_nothing_raised do
     FileBasedConfiguration.filepath
    end
  end
  
  def test_load
    pend
    #puts FileBasedConfiguration.load('Armagh::Connection::MongoConnection').inspect
  end
end