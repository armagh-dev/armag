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
ENV['RACK_ENV'] = 'test'

require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/admin/resource/api'

require 'test/unit'
require 'mocha/test_unit'

require 'rack/test'

require 'mongo'

class TestIntegrationResourceAPI < Test::Unit::TestCase
  def app
    Sinatra::Application
  end

  def self.startup
    load File.expand_path '../../../bin/armagh-resource-admin', __FILE__
    include Rack::Test::Methods
  end

  def setup
    MongoSupport.instance.clean_database
    authorize 'any', 'secret'
  end
end
