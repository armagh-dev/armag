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

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/models/model'

require 'test/unit'
require 'mocha/test_unit'

class ModelTest < Armagh::Models::Model
  def self.build
    new({'a' => 1})
  end
end

class ModelTest2 < Armagh::Models::Model
  def self.build
    new({'a' => 2})
  end
end

class TestModel < Test::Unit::TestCase
  def setup
    @collection = mock 'collection'
    @collection_error = ArgumentError.new('No collection specified.  Make sure <model>.default_collection is defined.')

    @values = {'value' => 'v'}
    @qualifier = {'qualifier' => 'q'}
  end

  def test_new
    assert_raise(NoMethodError){ModelTest.new({})}
  end

  def test_db_doc
    test = ModelTest.build
    assert_equal({'a' => 1}, test.db_doc)
    assert_equal({'a' => 1}.to_json,test.to_json)

    assert_not_equal(test.db_doc, ModelTest2.build.db_doc)
  end

  def test_create
    assert_raise(@collection_error) {ModelTest.db_create({})}

    result = mock
    @collection.expects(:insert_one).with(@values).returns result
    result.expects(:inserted_ids).returns ['id']

    assert_equal'id', ModelTest.db_create(@values, @collection)
  end

  def test_find_one
    assert_raise(@collection_error) {ModelTest.db_find_one({})}

    result = mock
    @collection.expects(:find).with(@qualifier).returns(result)
    result.expects(:limit).returns([1])
    assert_equal 1, ModelTest.db_find_one(@qualifier, @collection)
  end

  def test_find
    assert_raise(@collection_error) {ModelTest.db_find({})}

    result = [{'a' => 1}, {'b' => 2}]
    @collection.expects(:find).with(@qualifier).returns(result)
    assert_equal result, ModelTest.db_find(@qualifier, @collection)
  end

  def test_find_and_update
    assert_raise(@collection_error) {ModelTest.db_find_and_update({}, {})}

    result = [{'a' => 1}, {'b' => 2}]
    @collection.expects(:find_one_and_update).with(@qualifier, {:'$set' => @values}, {return_document: :after, upsert: true}).returns(result)
    assert_equal result, ModelTest.db_find_and_update(@qualifier, @values,@collection)
  end

  def test_update
    assert_raise(@collection_error) {ModelTest.db_update({}, {})}

    @collection.expects(:update_one).with(@qualifier, {:'$setOnInsert' => @values}, {upsert: true})
    ModelTest.db_update(@qualifier, @values,@collection)
  end

  def test_replace
    assert_raise(@collection_error) {ModelTest.db_replace({}, {})}

    @collection.expects(:replace_one).with(@qualifier, @values, {upsert: true})
    ModelTest.db_replace(@qualifier, @values,@collection)
  end

  def test_delete
    assert_raise(@collection_error) {ModelTest.db_delete({})}

    @collection.expects(:delete_one).with(@qualifier)
    ModelTest.db_delete(@qualifier, @collection)
  end
end
