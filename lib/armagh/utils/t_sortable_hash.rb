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

require 'tsort'

# Heavily inspired by example from tsort.rb packaged w/ ruby
module Armagh
  module Utils
    class TsortableHash < Hash
      include TSort

      alias tsort_each_node each_key

      def tsort_each_child(node, &block)
        result = self.[](node) || []
        result.each(&block)
      end
    end
  end
end