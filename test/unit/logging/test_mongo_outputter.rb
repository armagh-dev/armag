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

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../../lib/logging/mongo_outputter'
require_relative '../../helpers/mock_logger'

require 'log4r'
require 'test/unit'
require 'mocha/test_unit'

class TestMongoOutputter < Test::Unit::TestCase

  def setup
    @mongo_outputter = Log4r::MongoOutputter.new('outputter_name')

    @log = mock
    Armagh::Connection.stubs(:log).returns(@log)

    @resource_log = mock
    Armagh::Connection.stubs(:resource_log).returns(@resource_log)
  end

  def test_write
    data = {hash: true}
    @log.expects(:insert_one).with(data)
    @mongo_outputter.write(data)
  end

  def test_write_not_hash
    data = 'Invalid Data'
    e = assert_raise(ArgumentError) {@mongo_outputter.write(data)}
    assert_equal 'Data must be a hash.', e.message
  end

  def test_write_resource_log
    @mongo_outputter = Log4r::MongoOutputter.new('outputter_name', 'resource_log' => true)
    data = {hash: true}
    @resource_log.expects(:insert_one).with(data)
    @mongo_outputter.write(data)
  end

end