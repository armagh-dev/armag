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

#
# WARNING!!
#
# This file and the supporting ./armagh_env.json are set at the
# time of installation and cannot be changed.
#

require_relative 'configuration/file_based_configuration'
require_relative 'logging'

require_relative 'authentication/user'
require_relative 'authentication/group'

module Armagh
  module Environment
    
    def self.init
      unless @initialized
        init_env_vars
        Logging.init_log_env
        @initialized = true
      end
    end
    
    def self.init_env_vars
      env_hash = Armagh::Configuration::FileBasedConfiguration.load( 'ENV' )
      env_hash.each do |k,v|
        ENV[k] = v
      end
    end
  end
end

