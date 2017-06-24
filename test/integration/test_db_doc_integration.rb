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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'
require_relative '../../lib/armagh/connection'

require 'mocha/test_unit'

require 'mongo'

class Model1 < Armagh::Connection::DBDoc
  def self.default_collection
    Armagh::Connection::MongoConnection.instance.connection['c1']
  end
end

class Model2 < Armagh::Connection::DBDoc
  def self.default_collection
    Armagh::Connection::MongoConnection.instance.connection['c2']
  end
end

class TestModelIntegration < Test::Unit::TestCase
  def setup
    @collection = Armagh::Connection::MongoConnection.instance.connection['test_collection']
  end

  def teardown
    MongoSupport.instance.clean_database
  end

  def test_document_manipulation_with_collection
    Model1.db_create({'value' => true}, @collection)
    Model1.db_create({'value' => false}, @collection)
    assert_equal 2, Model1.db_find({}, @collection).to_a.length

    result = Model1.db_find({'value' => true}, @collection).to_a
    assert_equal 1, result.length
    one_result = Model1.db_find_one({'value' => true}, @collection)
    assert_equal result.first, one_result
    assert_true one_result['value']

    result = Model1.db_find({'value' => false}, @collection).to_a
    assert_equal 1, result.length
    one_result = Model1.db_find_one({'value' => false}, @collection)
    assert_equal result.first, one_result
    assert_false one_result['value']

    assert_empty Model1.db_find({'value' => 'none'}, @collection).to_a
    assert_nil Model1.db_find_one({'value' => 'none'}, @collection)

    result = Model1.db_find_and_update({'value' => false}, {'value' => true}, @collection)
    assert_true result['value']
    result = Model1.db_find({'value' => true}, @collection).to_a
    assert_equal 2, result.length
    assert_empty Model1.db_find({'value' => false}, @collection).to_a

    Model1.db_replace({'_id' => result.first['_id']}, {'new_value' => 'magic'}, @collection)
    result = Model1.db_find_one({'_id' => result.first['_id']}, @collection)
    assert_equal 'magic', result['new_value']

    assert_not_empty Model1.db_find({'new_value' => 'magic'}, @collection).to_a
    Model1.db_delete({'new_value' => 'magic'}, @collection)
    assert_empty Model1.db_find({'new_value' => 'magic'}, @collection).to_a

    assert_not_empty @collection.find({}).to_a
    assert_empty Model1.default_collection.find({}).to_a
  end

  def test_document_manipulation_without_collection
    Model1.db_create({'value' => true})
    Model1.db_create({'value' => false})
    assert_equal 2, Model1.db_find({}).to_a.length

    result = Model1.db_find({'value' => true}).to_a
    assert_equal 1, result.length
    one_result = Model1.db_find_one({'value' => true})
    assert_equal result.first, one_result
    assert_true one_result['value']

    result = Model1.db_find({'value' => false}).to_a
    assert_equal 1, result.length
    one_result = Model1.db_find_one({'value' => false})
    assert_equal result.first, one_result
    assert_false one_result['value']

    assert_empty Model1.db_find({'value' => 'none'}).to_a
    assert_nil Model1.db_find_one({'value' => 'none'})

    result = Model1.db_find_and_update({'value' => false}, {'value' => true})
    assert_true result['value']
    result = Model1.db_find({'value' => true}).to_a
    assert_equal 2, result.length
    assert_empty Model1.db_find({'value' => false}).to_a

    Model1.db_replace({'_id' => result.first['_id']}, {'new_value' => 'magic'})
    result = Model1.db_find_one({'_id' => result.first['_id']})
    assert_equal 'magic', result['new_value']

    assert_not_empty Model1.db_find({'new_value' => 'magic'}).to_a
    Model1.db_delete({'new_value' => 'magic'})
    assert_empty Model1.db_find({'new_value' => 'magic'}).to_a

    assert_empty @collection.find({}).to_a
    assert_not_empty Model1.default_collection.find({}).to_a
  end

  def test_default_collections
    assert_not_equal(Model2.default_collection.name, Model1.default_collection.name)
  end
end