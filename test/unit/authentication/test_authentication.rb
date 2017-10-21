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
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/authentication'

require 'test/unit'
require 'mocha/test_unit'

class TestAuthentication < Test::Unit::TestCase

  def setup
    @connection = mock('connection')
    Armagh::Connection.stubs(:config).returns(@connection)
  end

  def test_setup_authentication
    Armagh::Authentication::User.expects(:setup_default_users)
    Armagh::Authentication::Group.expects(:setup_default_groups)
    Armagh::Authentication::Configuration.expects(:find_or_create_configuration).with(
      @connection,
      Armagh::Authentication::Configuration::CONFIG_NAME,
      values_for_create: {},
      maintain_history: true
    )
    Armagh::Authentication.setup_authentication
  end

  def test_config
    Armagh::Authentication::Configuration.stubs(:find_or_create_configuration).with(
      @connection,
      Armagh::Authentication::Configuration::CONFIG_NAME,
      values_for_create: {},
      maintain_history: true
    ).returns(mock('config_object')).once

    assert_same(Armagh::Authentication.config, Armagh::Authentication.config)
  end
end