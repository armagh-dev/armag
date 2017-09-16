#
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
#
require 'singleton'

module Armagh
  module Actions
      
    class GemManager
      include Singleton

      def initialize
        @action_versions = {}
      end

      def activate_installed_gems(logger)
        return @action_versions unless @action_versions.empty?
        [ 'standard_actions', 'custom_actions' ].each do |action_module_path|
          action_module_name = action_module_path.gsub(/(?:^|_)([a-z])/) {$1.upcase}
          if Gem.try_activate "armagh/#{ action_module_path }"
            loaded_module_name, loaded_module_version = load_gem( action_module_name, action_module_path, logger )
            @action_versions[ loaded_module_name ] = loaded_module_version
          else
            logger.ops_warn "#{ action_module_name } gem is not deployed. These actions won't be available."
          end
        end
        @action_versions
      end
      
      def load_gem( action_module_name, action_module_path, logger )
        require "armagh/#{ action_module_path }"
        action_module = Armagh.const_get( action_module_name )
        loaded = [ action_module::NAME, action_module::VERSION ]
        logger.info "Using #{ loaded.join(": ")}"
        loaded
      end
     
    end
  end
end