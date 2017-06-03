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

require_relative '../../helpers/bson_support'
require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/connection'
require_relative '../../../lib/authentication/group'

require 'test/unit'
require 'mocha/test_unit'

class TestGroup < Test::Unit::TestCase

  def setup
    mock_mongo
  end

  def mock_mongo
    @connection = mock('connection')
    instance = mock
    instance.stubs(:connection).returns(@connection)

    @admin_connection = mock('admin_connection')
    admin_instance = mock
    admin_instance.stubs(:connection).returns(@admin_connection)

    Armagh::Connection::MongoConnection.stubs(:instance).returns(instance)
    Armagh::Connection::MongoAdminConnection.stubs(:instance).returns(admin_instance)
  end

  def create_group
    Armagh::Authentication::Group.any_instance.stubs(:save)
    group = Armagh::Authentication::Group.create(name: 'testgroup', description: 'description')
    group
  end

  def test_default_collection
    groups = mock('groups')
    Armagh::Connection.expects(:groups).returns(groups)
    assert_equal groups, Armagh::Authentication::Group.default_collection
  end

  def assert_default_group(name)
    Armagh::Authentication::Group.expects(:find_name).with(name).returns(nil)
    Armagh::Authentication::Group.expects(:db_create).with(has_entry('name', name))
  end

  def test_setup_default_groups
    assert_default_group 'super_administrators'
    assert_default_group 'administrators'
    assert_default_group 'user_administrators'
    assert_default_group 'user_managers'
    assert_default_group 'users'

    Armagh::Authentication::Group.setup_default_groups
  end

  def test_create
    group = create_group
    assert_equal Armagh::Authentication::Directory::INTERNAL, group.directory
    assert_equal 'testgroup', group.name
    assert_equal 'description', group.description

    Armagh::Authentication::Group.any_instance.expects(:save).raises(Armagh::Connection::DocumentUniquenessError.new('duplicate'))
    assert_raise(Armagh::Authentication::Group::NameError) {
      Armagh::Authentication::Group.create(name: 'testgroup', description: 'description')
    }
  end

  def test_update
    existing_group = mock('existing group')
    existing_group.expects(:name=).with('existing_group')
    existing_group.expects(:description=).with('description')
    existing_group.expects(:save)
    Armagh::Authentication::Group.expects(:find).with('id').returns(existing_group)

    group = Armagh::Authentication::Group.update(id: 'id', name: 'existing_group', description: 'description')
    assert_equal existing_group, group

    Armagh::Authentication::Group.expects(:find).with('new_id').returns(nil)
    assert_nil Armagh::Authentication::Group.update(id: 'new_id', name: 'new_group', description: 'description')
  end

  def test_find
    good_id = BSONSupport.random_object_id
    bad_id = BSONSupport.random_object_id
    Armagh::Authentication::Group.expects(:db_find_one).with(({'_id' => bad_id})).returns(nil)
    Armagh::Authentication::Group.expects(:db_find_one).with(({'_id' => good_id})).returns({'name' => 'name'})
    assert_nil Armagh::Authentication::Group.find(bad_id)
    valid = Armagh::Authentication::Group.find(good_id)
    assert_kind_of Armagh::Authentication::Group, valid
    assert_equal 'name', valid.name
  end

  def test_find_error
    e = Mongo::Error.new('error')
    Armagh::Authentication::Group.expects(:db_find_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::Group.find(BSONSupport.random_object_id)}
  end

  def test_find_name
    Armagh::Authentication::Group.expects(:db_find_one).with(({'name' => 'invalid'})).returns(nil)
    Armagh::Authentication::Group.expects(:db_find_one).with(({'name' => 'valid'})).returns({'name' => 'valid'})
    assert_nil Armagh::Authentication::Group.find_name('invalid')
    valid = Armagh::Authentication::Group.find_name('valid')
    assert_kind_of Armagh::Authentication::Group, valid
    assert_equal 'valid', valid.name
  end

  def test_find_name_error
    e = Mongo::Error.new('error')
    Armagh::Authentication::Group.expects(:db_find_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::Group.find_name('boom')}
  end

  def test_find_all
    groups = [{'name' => 'group1'}, {'name' => 'group2'}]
    Armagh::Authentication::Group.expects(:db_find).with({}).returns(groups)
    result = Armagh::Authentication::Group.find_all
    assert_kind_of Armagh::Authentication::Group, result.first
    assert_kind_of Armagh::Authentication::Group, result.last
    assert_equal 'group1', result.first.name
    assert_equal 'group2', result.last.name
  end

  def test_find_all_subset
    groups = [{'name' => 'group1'}, {'name' => 'group2'}]
    ids = BSONSupport.random_object_ids 5
    Armagh::Authentication::Group.expects(:db_find).with({'_id' => {'$in' => ids}}).returns(groups)
    result = Armagh::Authentication::Group.find_all(ids)
    assert_kind_of Armagh::Authentication::Group, result.first
    assert_kind_of Armagh::Authentication::Group, result.last
    assert_equal 'group1', result.first.name
    assert_equal 'group2', result.last.name
  end

  def test_find_all_error
    e = Mongo::Error.new('error')
    Armagh::Authentication::Group.expects(:db_find).raises(e)
    ids = BSONSupport.random_object_ids 5
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::Group.find_all(ids)}
  end

  def test_save_new
    group = Armagh::Authentication::Group.send(:new, {})
    group.name = 'name'
    group.description = 'description'
    Armagh::Authentication::Group.expects(:db_create).with(has_entries({'name' => group.name, 'description' => group.description}))
    group.save
  end

  def test_save_replace
    group = Armagh::Authentication::Group.send(:new, {'name' => 'testgroup', 'description' => 'description'})
    group.internal_id = 'id'
    group.name = 'name'
    group.description = 'description'
    Armagh::Authentication::Group.expects(:db_replace).with({'_id' => group.internal_id}, has_entries({'name' => group.name, 'description' => group.description}))
    group.save
  end

  def test_save_error
    e = Mongo::Error.new('error')
    group = Armagh::Authentication::Group.send(:new, name: 'testgroup', description: 'description')
    Armagh::Authentication::Group.expects(:db_create).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {group.save}
  end

  def test_delete
    user = mock('user')
    group = create_group
    group.internal_id = 123
    Armagh::Authentication::Group.expects(:db_delete).with({'_id' => 123})
    group.expects(:users).returns([user])
    group.expects(:remove_user).with(user)
    group.delete
  end

  def test_delete_error
    e = Mongo::Error.new('error')
    group = create_group
    group.expects(:users).returns([])
    Armagh::Authentication::Group.expects(:db_delete).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {group.delete}
  end

  def test_delete_permanent
    group = create_group
    group.mark_permanent
    assert_raise(Armagh::Authentication::Group::PermanentError) {group.delete}
  end

  def test_refresh
    group = create_group
    db_doc = group.db_doc.dup
    group.db_doc['some temp thing'] = 'blah'
    Armagh::Authentication::Group.expects(:db_find_one).with('_id' => group.internal_id).returns (db_doc)
    assert_not_equal db_doc, group.db_doc
    group.refresh
    assert_equal db_doc, group.db_doc
  end

  def test_name
    group = create_group
    group.name = 'something'
    assert_equal 'something', group.name
  end

  def test_description
    group = create_group
    group.description = 'something'
    assert_equal 'something', group.description
  end

  def test_directory
    group = create_group
    assert_equal Armagh::Authentication::Directory::INTERNAL, group.directory
    group.directory = Armagh::Authentication::Directory::LDAP
    assert_equal Armagh::Authentication::Directory::LDAP, group.directory
  end

  def test_users
    group = create_group
    assert_empty group.users

    user1 = stub({internal_id: '1', save: nil, username: 'user1'})
    user2 = stub({internal_id: '2', save: nil, username: 'user2'})
    user3 = stub({internal_id: '3', save: nil, username: 'user3'})

    user1.expects(:join_group).with(group, reciprocate: false)
    user2.expects(:join_group).with(group, reciprocate: false)

    group.add_user user1
    group.add_user user2

    assert_true group.has_user? user1
    assert_true group.has_user? user2
    assert_false group.has_user? user3

    Armagh::Authentication::User.expects(:find_all).with(%w(1 2)).returns([user1, user2])
    assert_equal [user1, user2], group.users

    user2.expects(:leave_group).with(group, reciprocate: false)
    group.remove_user(user2)

    assert_true group.has_user? user1
    assert_false group.has_user? user2
    assert_false group.has_user? user3

    assert_raise(Armagh::Authentication::Group::UserError.new("User 'user2' is not a member of 'testgroup'.")){group.remove_user(user2)}
  end

  def test_roles
    group = create_group
    assert_empty group.roles

    doc_role = Armagh::Authentication::Role.send(:new, name: 'specific doc', description: 'specific doc access', key: 'some_doc', published_collection_role: true)

    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::APPLICATION_ADMIN.key).returns(Armagh::Authentication::Role::APPLICATION_ADMIN)
    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::USER_MANAGER.key).returns(Armagh::Authentication::Role::USER_MANAGER)
    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::USER.key).returns(Armagh::Authentication::Role::USER)
    Armagh::Authentication::Role.stubs(:find).with(doc_role.key).returns(doc_role)

    group.add_role Armagh::Authentication::Role::APPLICATION_ADMIN
    group.add_role doc_role

    assert_true group.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_true group.has_role? doc_role
    assert_false group.has_role? Armagh::Authentication::Role::USER_MANAGER
    assert_equal [Armagh::Authentication::Role::APPLICATION_ADMIN, doc_role], group.roles

    group.remove_role doc_role

    assert_raise(Armagh::Authentication::Group::RoleError.new("Group 'testgroup' does not have a direct role of 'some_doc'.")){group.remove_role doc_role}

    assert_false group.has_role? doc_role
    assert_equal [Armagh::Authentication::Role::APPLICATION_ADMIN], group.roles

    group.remove_all_roles

    assert_empty group.roles
    assert_false group.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN

    assert_false group.has_role? doc_role
    group.add_role Armagh::Authentication::Role::USER
    assert_true group.has_role? Armagh::Authentication::Role::USER
    assert_true group.has_role? doc_role
  end

  def test_permanent
    group = create_group
    assert_false group.permanent?
    group.mark_permanent
    assert_true group.permanent?
  end

  def test_equality
    group1 = create_group
    group1.internal_id = 'id1'
    group2 = create_group
    group2.internal_id = 'id2'

    assert_false group1 == group2
    assert_false group1.eql? group2
    assert_not_equal group1.hash, group2.hash

    group2.internal_id = group1.internal_id

    assert_true group1 == group2
    assert_true group1.eql? group2
    assert_equal group1.hash, group2.hash
  end
end