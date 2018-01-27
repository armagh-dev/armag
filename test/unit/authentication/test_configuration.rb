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

require_relative '../../../lib/armagh/authentication/configuration'

require 'test/unit'
require 'mocha/test_unit'

class TestConfiguration < Test::Unit::TestCase

  def test_parameters
    assert_equal(%w(max_login_attempts min_password_length), Armagh::Authentication::Configuration.defined_parameters.collect{|p| p.name})
  end
end