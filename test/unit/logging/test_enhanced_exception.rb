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

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/logging/enhanced_exception'

require 'test/unit'

class TestEnhancedException < Test::Unit::TestCase

  def setup
    @additional_details = 'Some Details'
    @exception = RuntimeError.new('EXCEPTION')
    @ee = Armagh::Logging::EnhancedException.new(@additional_details, @exception)
  end

  def test_to_s
    assert_equal 'Some Details: RuntimeError => EXCEPTION', @ee.to_s
  end

  def test_inspect
    assert_equal 'Some Details: #<RuntimeError: EXCEPTION>', @ee.inspect
  end

end