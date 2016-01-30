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

require_relative 'interruptible_sleep'

gem 'exponential-backoff', '~> 0.0.2'
require 'exponential_backoff'

require 'logger'

module Armagh
  module Utils

    # Prevents resource contention
    class ProcessingBackoff

      attr_accessor :logger

      # @param max_backoff [Numeric] maximum number of seconds to backoff
      # @param min_interval [Numeric]
      # @param multiplier [Numeric]
      # @param randomization_factor [Numeric]
      def initialize(max_backoff = 500, min_interval = 1, multiplier = 1.75, randomization_factor= 0.3)
        max_elapsed = max_backoff/(1 + randomization_factor)

        @exponential_backoff = ExponentialBackoff.new(min_interval, max_elapsed)
        @exponential_backoff.multiplier = multiplier
        @exponential_backoff.randomize_factor = randomization_factor

        @logger = nil
      end

      # Backoff for the next backoff interval
      #
      # @return the amount of time for the backoff.
      def backoff
        sleep_time = @exponential_backoff.next_interval
        @logger.debug "Backing off for #{sleep_time} seconds" if @logger

        sleep sleep_time
        sleep_time
      end

      # Backoff for the next backoff intervaling allow for interruptions
      #
      # @example backoff unless the runner terminates
      #   interruptible_backoff { runner.terminated? }
      #
      # @yield  the condition that is checked for interrupt (if true, interrupt)
      # @return the amount of time for the backoff.  If interrupted, this is the planned backoff time
      def interruptible_backoff
        sleep_time = @exponential_backoff.next_interval
        @logger.debug "Backing off for #{sleep_time} seconds" if @logger

        InterruptibleSleep::interruptible_sleep(sleep_time) { yield }
        sleep_time
      end


      # Reset the backoff interval
      def reset
        @exponential_backoff.clear
      end
    end
  end
end