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

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/environment'
Armagh::Environment.init

require_relative '../../helpers/mock_logger'
require_relative '../../../lib/utils/interruptible_sleep'
require 'test/unit'

class TestInterruptibleSleep < Test::Unit::TestCase

  def setup
  end

  def test_interruptible_sleep_complete
    sleep_time = 2
    start = Time.now
    Armagh::Utils::InterruptibleSleep.interruptible_sleep(sleep_time) { false }
    elapsed = Time.now - start
    assert_equal(sleep_time, elapsed.round)
  end

  def test_interruptible_sleep_interrupt
    sleep_time = 10
    interrupt_time = 1
    start = Time.now
    Armagh::Utils::InterruptibleSleep.interruptible_sleep(sleep_time) { Time.now > start + interrupt_time }
    elapsed = Time.now - start
    assert_equal(interrupt_time, elapsed.round)
  end
end