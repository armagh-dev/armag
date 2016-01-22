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
require_relative '../../lib/connection'
require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestMongoConnection < Test::Unit::TestCase

  def test_mongo_connection
    Mongo::Client.any_instance.stubs(:create_from_uri)
    orig_strl = ENV['ARMAGH_STRL']
    ENV['ARMAGH_STRL'] = 'strl'
    assert_kind_of(Mongo::Client, Class.new(Armagh::Connection::MongoConnection).instance.connection)

    if orig_strl
      ENV['ARMAGH_STRL'] = orig_strl
    else
      ENV.delete 'ARMAGH_STRL'
    end
  end

  def test_mongo_connection_no_env
    orig_strl = ENV['ARMAGH_STRL']
    ENV.delete 'ARMAGH_STRL' if orig_strl

    e = assert_raise do
      Class.new(Armagh::Connection::MongoConnection).instance.connection
    end

    assert_equal('No connection string defined.  Define a base-64 encoded mongo connection URI in env variable ARMAGH_STRL.', e.message)

    ENV['ARMAGH_STRL'] = orig_strl if orig_strl
  end
end
