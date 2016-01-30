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
require_relative '../../test/test_helpers/mock_global_logger'
require_relative '../../lib/utils/processing_backoff'
require 'test/unit'

class TestProcessingBackoff < Test::Unit::TestCase

  def setup
    @max_time = 500
    @processing_backoff = Armagh::Utils::ProcessingBackoff.new(@max_time)
  end

  def test_backoff
    backoffs = []
    3.times do
      backoffs << @processing_backoff.backoff
    end

    backoffs.each do |backoff|
      assert_true backoff < @max_time
    end

    assert_equal(3, backoffs.uniq.length)
  end

  def test_interruptable_backoff
    interrupt_time = 0.1
    backoff_time = 0

    until backoff_time > 2
      start = Time.now
      backoff_time = @processing_backoff.interruptible_backoff { Time.now > start + interrupt_time}
      elapsed = Time.now - start
    end

    assert_true(elapsed < backoff_time)
  end

  def test_reset
    no_reset_times = []
    5.times do
      no_reset_times << @processing_backoff.interruptible_backoff {true}
    end
    max_no_reset = no_reset_times.max

    @processing_backoff.reset

    reset_times = []
    5.times do
      reset_times << @processing_backoff.interruptible_backoff{true}
      @processing_backoff.reset
    end
    max_reset = reset_times.max
    assert_true(max_no_reset > 2)
    assert_true(max_reset < 2)
  end
end