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

module Armagh
  module Configuration
    module ActionConfigValidator
      def validate(action_config)
        # TODO Implement action config validation here

        # Things to validate:
        # * Missing action fields (like doctypes)
        # * Call Action validation (probably need to clean up that error reporting)
        # * A given type/state pair can only be used for a single Parser, Publisher, or Collector
        # * A collector can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A parser can only take a ready document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document gets deleted
        # * A subscriber can only take a published document in, can only produce n document types that are all ready or working.  out types can not be the same as in types  the incoming document does not get changed
        # * A publisher only takes a document type (no state -- ready -> published is implied). it's only job is to publish that document.
      end
    end
  end
end
