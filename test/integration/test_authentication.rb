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
require_relative '../helpers/bson_support'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/authentication'
require_relative '../../lib/armagh/connection'

require 'test/unit'

class TestAuthentication < Test::Unit::TestCase

  def setup
    MongoSupport.instance.clean_database
    Armagh::Connection.setup_indexes
    Armagh::Authentication.setup_authentication
  end

  def test_user
    # Create duplicates
    Armagh::Authentication::User.create(username: 'user1', password: 'testpassword', name: 'User1', email: 'user1@test.com')
    assert_raise(Armagh::Authentication::User::UsernameError.new("A user with username 'user1' already exists.")){
      Armagh::Authentication::User.create(username: 'user1', password: 'anotherpassword', name: 'duplicate', email: 'duplicate@test.com')
    }

    # Update nonexistent
    assert_nil Armagh::Authentication::User.update(id: BSONSupport.random_object_id, username: 'user2', password: 'testpassword', name: 'User2', email: 'user2@test.com')
    user = Armagh::Authentication::User.create(username: 'user2', password: 'testpassword', name: 'User2', email: 'user2@test.com')
    assert_equal user, Armagh::Authentication::User.update(id: user.internal_id, username: 'user2', password: 'testpassword', name: 'User2', email: 'user2@test.com')
  end

  def test_group
    # Create duplicates
    Armagh::Authentication::Group.create(name: 'group1', description: 'Test Group')
    assert_raise(Armagh::Authentication::Group::NameError.new("A group with name 'group1' already exists.")){
      Armagh::Authentication::Group.create(name: 'group1', description: 'Test Group 2')
    }

    # Update nonexistent
    assert_nil Armagh::Authentication::Group.update(id: BSONSupport.random_object_id, name: 'group2', description: 'Test Group')
    group = Armagh::Authentication::Group.create(name: 'group2', description: 'test group')
    assert_equal group, Armagh::Authentication::Group.update(id: group.internal_id, name: 'group2', description: 'test group')
  end

  def test_user_group_membership
    user1 = Armagh::Authentication::User.create(username: 'user1', password: 'testpassword', name: 'User1', email: 'user1@test.com')
    user2 = Armagh::Authentication::User.create(username: 'user2', password: 'testpassword', name: 'User2', email: 'user2@test.com')

    group1 = Armagh::Authentication::Group.create(name: 'group_1', description: 'test group')
    group2 = Armagh::Authentication::Group.create(name: 'group_2', description: 'test group')

    user1.join_group group1
    group1.add_user user2

    group1.save
    group2.save

    assert_true group1.has_user? user1
    assert_true group1.has_user? user2
    assert_false group2.has_user? user1
    assert_false group2.has_user? user2

    assert_true user1.member_of? group1
    assert_true user2.member_of? group1

    assert_false user1.member_of? group2
    assert_false user2.member_of? group2

    user1.delete
    group1.refresh
    assert_false group1.has_user? user1

    assert_true user2.member_of? group1
    group1.delete
    user2.refresh
    assert_false user2.member_of? group1
  end

  def test_permissions
    user1 = Armagh::Authentication::User.create(username: 'user1', password: 'testpassword', name: 'User1', email: 'user1@test.com')
    user2 = Armagh::Authentication::User.create(username: 'user2', password: 'testpassword', name: 'User2', email: 'user2@test.com')

    group1 = Armagh::Authentication::Group.create(name: 'group_1', description: 'test group')
    group2 = Armagh::Authentication::Group.create(name: 'group_2', description: 'test group')

    pub_collection = MongoSupport.instance.create_collection('documents.PubType')
    doctype_role = Armagh::Authentication::Role.published_collection_role(pub_collection)

    user1.join_group group1
    user1.join_group group2
    user2.join_group group2

    user1.add_role Armagh::Authentication::Role::RESOURCE_ADMIN
    user1.add_role Armagh::Authentication::Role::USER

    user2.add_role Armagh::Authentication::Role::APPLICATION_ADMIN
    user2.add_role doctype_role

    group1.add_role Armagh::Authentication::Role::USER_ADMIN
    group2.add_role Armagh::Authentication::Role::USER

    user1.save
    user2.save
    group1.save
    group2.save

    # User 1 direct
    assert_true user1.has_role? Armagh::Authentication::Role::RESOURCE_ADMIN
    assert_true user1.has_role? Armagh::Authentication::Role::USER

    # User1 indirect
    assert_true user1.has_role? doctype_role

    # User1 through Groups
    assert_true user1.has_role? Armagh::Authentication::Role::USER_ADMIN

    # User1 no
    assert_false user1.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN

    # User2 direct
    assert_true user2.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_true user2.has_role? doctype_role

    # User2 through groups
    assert_true user2.has_role? Armagh::Authentication::Role::USER

    # User2 no
    assert_false user2.has_role? Armagh::Authentication::Role::RESOURCE_ADMIN
  end
end
