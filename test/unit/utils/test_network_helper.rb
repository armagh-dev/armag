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

require 'test/unit'

require_relative '../../../lib/armagh/utils/network_helper'

class TestNetworkHelper < Test::Unit::TestCase

  def test_local
    a = '127.0.0.1'
    assert_true Armagh::Utils::NetworkHelper.local?(a)

    a = '127.9.9.1'
    assert_true Armagh::Utils::NetworkHelper.local?(a)

    a = '0.0.0.0'
    assert_true Armagh::Utils::NetworkHelper.local?(a)

    a = '8.8.8.8'
    assert_false Armagh::Utils::NetworkHelper.local?(a)

    a = `hostname`.strip
    assert_true Armagh::Utils::NetworkHelper.local?(a)

    a = 'google.com'
    assert_false Armagh::Utils::NetworkHelper.local?(a)

    a = 'localhost'
    assert_true Armagh::Utils::NetworkHelper.local?(a)
  end

end