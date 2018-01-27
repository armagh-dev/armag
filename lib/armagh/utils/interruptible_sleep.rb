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

module Armagh
  module Utils
    class InterruptibleSleep

      # A sleep that is able to be interrupted.
      #
      # @example Sleep for 10 seconds unless the runner is terminated
      #   sleep(10) { runner.terminated? }
      #
      # @param sleep_time [Numeric] the time to sleep
      # @yield  the condition that is checked for interrupt (if true, interrupt)
      def self.interruptible_sleep(sleep_time)
        whole = sleep_time.to_i
        partial = sleep_time - whole

        whole.times do
          break if yield
          sleep 1
        end

        sleep partial unless yield
      end

      nil
    end
  end
end
