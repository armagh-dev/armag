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
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/connection'
require 'test/unit'
require 'mocha/test_unit'

class TestMongoErrorHandler < Test::Unit::TestCase
  def test_convert_size
    e = Armagh::Connection.convert_mongo_exception(Mongo::Error::MaxBSONSize.new('size'))
    assert_kind_of(Armagh::Connection::DocumentSizeError, e)
  end

  def test_convert_unique
    e = Armagh::Connection.convert_mongo_exception(Mongo::Error::OperationFailure.new('E11000: something'))
    assert_kind_of(Armagh::Connection::DocumentUniquenessError, e)
  end

  def test_convert_other_operation
    e = Armagh::Connection.convert_mongo_exception(Mongo::Error::OperationFailure.new('E11999: something'))
    assert_kind_of(Armagh::Connection::ConnectionError, e)
  end

  def test_convert_mongo_error
    e = Armagh::Connection.convert_mongo_exception(Mongo::Error.new('mongo error'))
    assert_kind_of(Armagh::Connection::ConnectionError, e)
  end

  def test_convert_other_error
    e = Armagh::Connection.convert_mongo_exception(EncodingError.new('encoding'))
    assert_kind_of(EncodingError, e)
  end

  def test_convert_with_id
    e = Armagh::Connection.convert_mongo_exception(Mongo::Error::MaxBSONSize.new('size'), natural_key: 'TestMongoErrorHandler document_id')
    assert_equal 'TestMongoErrorHandler document_id is too large.  Consider using a divider or splitter to break up the document.', e.message
  end
end