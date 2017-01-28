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

require 'thin'

module Armagh
  module Admin
    module Application
    
      class ThinBackend < ::Thin::Backends::TcpServer

        def initialize( host, port, options )
          super( host, port )
          api = Armagh::Admin::Application::API.instance
          if api.using_ssl?
            @ssl         = true
            @ssl_options = options
          end
        end
      end
    end
  end
end 