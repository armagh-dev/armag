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

require_relative '../../../helpers/coverage_helper'

require_relative '../../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../../lib/armagh/admin/resource/api'

require_relative '../../../helpers/armagh_test'


require 'test/unit'
require 'mocha/test_unit'


class TestResourceApplicationAPI < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @logger = mock_logger

    Armagh::Connection.stubs(:require_connection)
    @api = Armagh::Admin::Resource::API.instance
  end

  def test_init_checks_connection
    Armagh::Connection.unstub(:require_connection)
    Armagh::Connection.expects(:require_connection)
    Armagh::Admin::Resource::API.send(:new)
  end
end