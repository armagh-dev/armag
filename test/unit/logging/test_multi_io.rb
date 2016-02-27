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
require_relative '../../../lib/logging/multi_io'

require 'test/unit'
require 'mocha/test_unit'

class TestMultiIO < Test::Unit::TestCase
  def setup
    @io1 = mock
    @io2 = mock
    @multi_io = Armagh::Logging::MultiIO.new(@io1, @io2)
  end

  def test_write
    str = 'test write'
    @io1.expects(:write).with(str)
    @io2.expects(:write).with(str)
    @multi_io.write(str)
  end

  def test_close
    @io1.expects(:close)
    @io2.expects(:close)
    @multi_io.close
  end
end