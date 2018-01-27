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

require_relative '../../helpers/coverage_helper'
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/authentication/role'

require 'test/unit'
require 'mocha/test_unit'

class TestRole < Test::Unit::TestCase

  def setup
  end

  def test_all_roles
    published_collection = mock('collection')
    published_collection.stubs(:name).returns('documents.PublishedDocumentTypes')
    Armagh::Connection.expects(:all_published_collections).returns([published_collection])
    actual = Armagh::Authentication::Role.all

    assert_equal Armagh::Authentication::Role::PREDEFINED_ROLES.length + 1, actual.length
    Armagh::Authentication::Role::PREDEFINED_ROLES.each do |role|
      assert_include actual, role
      assert_false role.published_collection_role?
    end

    published = (actual - Armagh::Authentication::Role::PREDEFINED_ROLES).first
    assert_equal('doc_PublishedDocumentTypes_user', published.internal_id)
    assert_true published.published_collection_role?
  end

  def test_published_collection_role
    published_collection = mock
    published_collection.expects(:name).returns('documents.SomeTypeCollection')
    role = Armagh::Authentication::Role.published_collection_role published_collection
    assert_kind_of Armagh::Authentication::Role, role
    assert_true role.published_collection_role?
  end

  def test_find_from_published_collection
    doctype = 'SomeDocType'
    doc_collection = mock
    doc_collection.expects(:name).returns("documents.#{doctype}")

    Armagh::Connection.expects(:all_published_collections).returns([])

    assert_nil Armagh::Authentication::Role.find_from_published_doctype(doctype)

    Armagh::Connection.expects(:all_published_collections).returns([doc_collection])
    role = Armagh::Authentication::Role.find_from_published_doctype(doctype)
    assert_equal(Armagh::Authentication::Role.key_from_published_doctype(doctype),role.internal_id)
  end

  def test_find
    Armagh::Connection.stubs(:all_published_collections).returns([])
    assert_nil Armagh::Authentication::Role.find('invalid')
    assert_equal Armagh::Authentication::Role::APPLICATION_ADMIN, Armagh::Authentication::Role.find(Armagh::Authentication::Role::APPLICATION_ADMIN.internal_id)
  end

  def test_equal
    assert_true Armagh::Authentication::Role::APPLICATION_ADMIN == Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_false Armagh::Authentication::Role::APPLICATION_ADMIN == Armagh::Authentication::Role::RESOURCE_ADMIN

    assert_true Armagh::Authentication::Role::APPLICATION_ADMIN.eql?(Armagh::Authentication::Role::APPLICATION_ADMIN)
    assert_false Armagh::Authentication::Role::APPLICATION_ADMIN.eql?(Armagh::Authentication::Role::RESOURCE_ADMIN)
  end

  def test_to_json
    role = Armagh::Authentication::Role::APPLICATION_ADMIN
    expected = {
        'name' => role.name,
        'description' => role.description,
        'internal_id' => role.internal_id,
        'published_collection_role' => role.published_collection_role?
    }.to_json
    assert_equal(expected, Armagh::Authentication::Role::APPLICATION_ADMIN.to_json)
  end

end