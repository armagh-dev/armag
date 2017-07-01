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

module Armagh
  module Utils
    class ActionHelper
      class ActionClassError < StandardError; end

      def self.get_action_super(type)
        type = type.class unless type.is_a? Class

        raise ActionClassError, "#{type} is not a known action type." unless Actions.defined_actions.include?(type)

        superclass_name = type.superclass.to_s
        superclass_name.sub!(/^Armagh::Actions::/, '') ? superclass_name : get_action_super(type.superclass)
      end
    end
  end
end