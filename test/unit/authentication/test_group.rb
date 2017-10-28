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

require_relative '../../helpers/armagh_test'
require_relative '../../helpers/bson_support'
require_relative '../../helpers/coverage_helper'
require_relative '../../../lib/armagh/connection'
require_relative '../../../lib/armagh/authentication/group'

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

    @group_coll = mock
    Armagh::Connection.stubs( :groups ).returns( @group_coll )

    @user_coll = mock
    Armagh::Connection.stubs( :users ).returns( @user_coll )
  end

  def create_group( returned_id = 123 )
    @group_coll.expects( :insert_one ).returns( mock( inserted_ids: [returned_id] ))
    group = Armagh::Authentication::Group.create(name: 'testgroup', description: 'description')
    group
  end

  def test_default_collection
    groups = mock('groups')
    Armagh::Connection.expects(:groups).returns(groups)
    assert_equal groups, Armagh::Authentication::Group.default_collection
  end

  def assert_default_group(name)
    Armagh::Authentication::Group.expects(:find_by_name).with(name).returns(nil)
    @group_coll.expects(:insert_one).with(has_entry('name', name)).returns( mock( inserted_ids: [ name ]))
  end

  def test_setup_default_groups
    assert_default_group 'super_administrators'
    assert_default_group 'administrators'
    assert_default_group 'user_administrators'
    assert_default_group 'users'

    Armagh::Authentication::Group.setup_default_groups
  end

  def test_create
    group = create_group
    assert_equal Armagh::Authentication::Directory::INTERNAL, group.directory
    assert_equal 'testgroup', group.name
    assert_equal 'description', group.description

    @group_coll.expects(:insert_one).raises(Armagh::Connection::DocumentUniquenessError.new('duplicate'))
    assert_raise(Armagh::Authentication::Group::NameError) {
      Armagh::Authentication::Group.create(name: 'testgroup', description: 'description')
    }
  end

  def test_update
    existing_group = mock('existing group')
    existing_group.expects(:name=).with('existing_group')
    existing_group.expects(:description=).with('description')
    existing_group.expects(:save)
    Armagh::Authentication::Group.expects(:get).with('id').returns(existing_group)

    group = Armagh::Authentication::Group.update(id: 'id', name: 'existing_group', description: 'description')
    assert_equal existing_group, group

    Armagh::Authentication::Group.expects(:get).with('new_id').returns(nil)
    assert_nil Armagh::Authentication::Group.update(id: 'new_id', name: 'new_group', description: 'description')
  end

   def test_find_by_name
    Armagh::Authentication::Group.expects(:find_one).with(({'name' => 'invalid'})).returns(nil)
    Armagh::Authentication::Group.stubs(:save)
    valid_returned = create_group
    valid_returned.name = 'valid'
    Armagh::Authentication::Group.expects(:find_one).with(({'name' => 'valid'})).returns(valid_returned)
    assert_nil Armagh::Authentication::Group.find_by_name('invalid')
    valid = Armagh::Authentication::Group.find_by_name('valid')
    assert_kind_of Armagh::Authentication::Group, valid
    assert_equal 'valid', valid.name
  end

  def test_find_by_name_error
    e = Mongo::Error.new('error')
    @group_coll.expects(:find).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::Group.find_by_name('boom')}
  end

  def test_find_all
    groups = []
    (1..2).each do |i|
      group = create_group(i)
      group.name = "group#{i}"
      image =  group.to_hash
      image[ '_id' ] = image[ 'internal_id']
      image.delete 'internal_id'
      groups << image
    end

    @group_coll.expects(:find).with({}).returns(groups)
    result = Armagh::Authentication::Group.find_all
    assert_kind_of Armagh::Authentication::Group, result.first
    assert_kind_of Armagh::Authentication::Group, result.last
    assert_equal 'group1', result.first.name
    assert_equal 'group2', result.last.name
  end

  def test_find_all_subset
    groups = []
    (1..2).each do |i|
      group = create_group(i)
      group.name = "group#{i}"
      image = group.to_hash
      image[ '_id' ] = image[ 'internal_id']
      image.delete 'internal_id'
      groups << image
    end
    ids = BSONSupport.random_object_ids 5
    @group_coll.expects(:find).with({'_id' => {'$in' => ids}}).returns(groups)
    result = Armagh::Authentication::Group.find_all(ids)
    assert_kind_of Armagh::Authentication::Group, result.first
    assert_kind_of Armagh::Authentication::Group, result.last
    assert_equal 'group1', result.first.name
    assert_equal 'group2', result.last.name
  end

  def test_find_all_error
    e = Mongo::Error.new('error')
    @group_coll.expects(:find).raises(e)
    ids = BSONSupport.random_object_ids 5
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::Group.find_all(ids)}
  end

  def test_save_new
    group = Armagh::Authentication::Group.send(:new, {})
    group.name = 'name'
    group.description = 'description'
    @group_coll.expects(:insert_one).with(has_entries({'name' => group.name, 'description' => group.description})).returns(mock(inserted_ids:[123]))
    group.save
  end

  def test_save_replace
    group = create_group( 123 )
    group.name = 'name'
    group.description = 'description'
    @group_coll.expects(:replace_one).with({'_id' => group.internal_id}, has_entries({'name' => group.name, 'description' => group.description}), {:upsert => true })
    group.save
  end

  def test_save_error
    e = Mongo::Error.new('error')
    group = Armagh::Authentication::Group.send(:new, { 'name' => 'testgroup', 'description' => 'description' })
    @group_coll.expects(:insert_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {group.save}
  end

  def test_delete
    group = create_group
    user = mock
    @group_coll.expects(:delete_one).with({'_id' => 123})
    group.stubs(:users).returns([user])
    user.expects(:leave_group).with(group, {:reciprocate => false})
    user.expects(:save)
    group.expects(:remove_item_from_users)
    group.delete
  end

  def test_delete_error
    e = Mongo::Error.new('error')
    group = create_group
    group.expects(:users).returns([])
    @group_coll.expects(:delete_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {group.delete}
  end

  def test_delete_permanent
    group = create_group
    group.mark_permanent
    assert_raise(Armagh::Authentication::Group::PermanentError) {group.delete}
  end

  def test_refresh
    group = create_group
    group_image = group.to_hash
    group_image[ '_id' ] = group_image[ 'internal_id']
    group_image.delete 'internal_id'
    group2 = create_group
    group2.name = 'tom'
    @group_coll.expects(:find).with({'_id' => group.internal_id}).returns(mock(limit: [group_image]))
    assert_not_same group2, group
    group2.refresh
    assert_equal group2, group
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

    user1 = stub({internal_id: '1', save: nil, username: 'user1' })
    user2 = stub({internal_id: '2', save: nil, username: 'user2'})
    user3 = stub({internal_id: '3', save: nil, username: 'user3'})
    [user1,user2,user3].each do |u|
      def u.is_a?( klass )
        klass == Armagh::Authentication::User
      end
    end

    user1.expects(:join_group).with(group, reciprocate: false)
    user2.expects(:join_group).with(group, reciprocate: false)

    group.add_user user1
    group.add_user user2
    group.add_user user2

    assert_true group.has_user? user1
    assert_true group.has_user? user2
    assert_false group.has_user? user3

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

    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::APPLICATION_ADMIN.internal_id).returns(Armagh::Authentication::Role::APPLICATION_ADMIN)
    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::USER_ADMIN.internal_id).returns(Armagh::Authentication::Role::USER_ADMIN)
    Armagh::Authentication::Role.stubs(:find).with(Armagh::Authentication::Role::USER.internal_id).returns(Armagh::Authentication::Role::USER)
    Armagh::Authentication::Role.stubs(:find).with(doc_role.internal_id).returns(doc_role)

    group.add_role Armagh::Authentication::Role::APPLICATION_ADMIN
    group.add_role doc_role

    assert_true group.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_true group.has_role? doc_role
    assert_false group.has_role? Armagh::Authentication::Role::USER_ADMIN
    assert_equal [Armagh::Authentication::Role::APPLICATION_ADMIN, doc_role], group.roles

    group.remove_role doc_role

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
    group1 = create_group( 'id1')
    group2 = create_group( 'id2' )

    assert_false group1 == group2
    assert_false group1.eql? group2
    assert_not_equal group1.hash, group2.hash

    assert_true group1 == group1
    assert_true group1.eql? group1
    assert_equal group1.hash, group1.hash
  end
end