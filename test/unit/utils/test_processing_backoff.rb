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

require_relative '../../../lib/armagh/utils/processing_backoff'
require 'test/unit'

class TestProcessingBackoff < Test::Unit::TestCase

  def setup
    @max_time = 60
    @processing_backoff = Armagh::Utils::ProcessingBackoff.new(@max_time)
  end

  def test_backoff
    backoffs = []
    3.times do
      backoffs << @processing_backoff.backoff
    end

    backoffs.each do |backoff|
      assert_true backoff <= @max_time
    end

    assert_equal(3, backoffs.length)
  end

  def test_interruptable_backoff
    interrupt_time = 0.1
    backoff_time = 0

    until backoff_time >2
      start = Time.now
      backoff_time = @processing_backoff.interruptible_backoff { Time.now > start + interrupt_time }
      elapsed = Time.now - start
    end

    assert_true(elapsed < backoff_time)
  end

  def test_reset
    max_reset = 0
    100.times { max_reset = [@processing_backoff.interruptible_backoff { true }, max_reset].max }
    @processing_backoff.reset
    assert_true max_reset > @processing_backoff.interruptible_backoff { true }
  end
end