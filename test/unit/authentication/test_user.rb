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
require_relative '../../helpers/bson_support'
require_relative '../../../lib/armagh/connection'
require_relative '../../../lib/armagh/authentication/user'
require_relative '../../../lib/armagh/connection'
require_relative '../../../lib/armagh/authentication'

require 'test/unit'
require 'mocha/test_unit'

class TestUser < Test::Unit::TestCase

  def setup
    mock_mongo
    Armagh::Authentication::User.setup_default_users
  end

  def mock_mongo
    @connection = mock('connection')
    instance = mock
    instance.stubs(:connection).returns(@connection)

    @users = mock('users')
    @connection.stubs(:[]).with('users').returns(@users)
    @users.stubs(:replace_one)

    @admin_user = mock('admin_user')
    @admin_user.stubs({remove_all_roles: nil, add_role: nil, save: nil})
    Armagh::Authentication::User.stubs(:find_username).with(Armagh::Authentication::User::ADMIN_USERNAME).returns(@admin_user)

    @dummy_user = mock('dummy_user')
    @dummy_user.stubs({save: nil, db_doc: {'attempted_usernames' => {}}})
    Armagh::Authentication::User.stubs(:find_username).with(Armagh::Authentication::User::DUMMY_USERNAME).returns(@dummy_user)

    @admin_connection = mock('admin_connection')
    admin_instance = mock
    admin_instance.stubs(:connection).returns(@admin_connection)

    Armagh::Connection::MongoConnection.stubs(:instance).returns(instance)
    Armagh::Connection::MongoAdminConnection.stubs(:instance).returns(admin_instance)
  end

  def create_user
    Armagh::Authentication::User.any_instance.stubs(:save)
    user = Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com')
    user
  end

  def test_default_collection
    Armagh::Connection.expects(:users).returns(@users)
    assert_equal @users, Armagh::Authentication::User.default_collection
  end

  def test_setup_default_users
    Armagh::Authentication::User.expects(:find_username).with(Armagh::Authentication::User::ADMIN_USERNAME).returns(nil)
    Armagh::Authentication::User.expects(:db_create).with(has_entry('username', Armagh::Authentication::User::ADMIN_USERNAME))

    Armagh::Authentication::User.expects(:find_username).with(Armagh::Authentication::User::DUMMY_USERNAME).returns(nil)
    Armagh::Authentication::User.expects(:db_create).with(has_entry('username', Armagh::Authentication::User::DUMMY_USERNAME))

    Armagh::Authentication::User.setup_default_users
  end

  def test_create
    Armagh::Authentication::User.expects(:db_create).times(3)

    user = Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com')
    assert_not_empty user.hashed_password
    assert_equal Armagh::Authentication::Directory::INTERNAL, user.directory

    user = Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com', directory: Armagh::Authentication::Directory::INTERNAL)
    assert_not_empty user.hashed_password
    assert_equal Armagh::Authentication::Directory::INTERNAL, user.directory

    user = Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com', directory: Armagh::Authentication::Directory::LDAP)
    assert_equal Armagh::Authentication::Directory::LDAP, user.directory
    assert_raise(Armagh::Authentication::User::DirectoryError) {user.hashed_password}

    Armagh::Authentication::User.any_instance.expects(:save).raises(Armagh::Connection::DocumentUniquenessError.new('not unique'))
    assert_raise(Armagh::Authentication::User::UsernameError) {
      Armagh::Authentication::User.create(username: 'testuser', password: 'testpassword', name: 'Test User', email: 'test@user.com', directory: Armagh::Authentication::Directory::LDAP)
    }
  end

  def test_update
    existing_user = mock('existing user')
    existing_user.expects(:username=).with('existing_user')
    existing_user.expects(:password=).with('testpassword')
    existing_user.expects(:name=).with('test user')
    existing_user.expects(:email=).with('test@email.com')
    existing_user.expects(:save)
    Armagh::Authentication::User.expects(:find).with('id').returns(existing_user)

    user = Armagh::Authentication::User.update(id: 'id', username: 'existing_user', password: 'testpassword', name: 'test user', email: 'test@email.com')
    assert_equal existing_user, user


    Armagh::Authentication::User.expects(:find).with('new_id').returns(nil)
    assert_nil Armagh::Authentication::User.update(id: 'new_id', username: 'new_user', password: 'testpassword', name: 'test user', email: 'test@email.com')
  end

  def test_find_username
    result = {'username' => 'testuser'}
    Armagh::Authentication::User.expects(:db_find_one).with({'username' => 'username'}).returns(result).twice
    Armagh::Authentication::User.unstub(:find_username)
    assert_equal('testuser', Armagh::Authentication::User.find_username('username').username)
    assert_equal('testuser', Armagh::Authentication::User.find_username('UsErNaMe').username)
  end

  def test_find_username_none
    Armagh::Authentication::User.unstub(:find_username)
    Armagh::Authentication::User.expects(:db_find_one).returns(nil)
    assert_nil Armagh::Authentication::User.find_username('username')
  end

  def test_find_username_error
    Armagh::Authentication::User.unstub(:find_username)
    e = Mongo::Error.new('error')
    Armagh::Authentication::User.expects(:db_find_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::User.find_username('username')}
  end

  def test_find
    id = BSONSupport.random_object_id
    result = {'username' => 'testuser'}
    Armagh::Authentication::User.expects(:db_find_one).with({'_id' => id}).returns(result)
    user = Armagh::Authentication::User.find(id)
    assert_equal('testuser', user.username)
  end

  def test_find_none
    id = BSONSupport.random_object_id
    Armagh::Authentication::User.expects(:db_find_one).returns(nil)
    assert_nil Armagh::Authentication::User.find(id)
  end

  def test_find_error
    id = BSONSupport.random_object_id
    e = Mongo::Error.new('error')
    Armagh::Authentication::User.expects(:db_find_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::User.find(id)}
  end

  def test_find_all
    result = [{'username' => 'testuser1'}, nil, {'username' => 'testuser3'}, {'username' => 'testuser4'}, ]
    Armagh::Authentication::User.expects(:db_find).with({}).returns(result)
    users = Armagh::Authentication::User.find_all
    assert_equal 3, users.length

    users.each do |user|
      assert_kind_of Armagh::Authentication::User, user
    end

    assert_equal 'testuser1', users[0].username
    assert_equal 'testuser3', users[1].username
    assert_equal 'testuser4', users[2].username
  end

  def test_find_all_subset
    ids = BSONSupport.random_object_ids(4)
    result = [{'username' => 'testuser1'}, nil, {'username' => 'testuser3'}, {'username' => 'testuser4'}, ]
    Armagh::Authentication::User.expects(:db_find).with({'_id' => {'$in' => ids}}).returns(result)

    users = Armagh::Authentication::User.find_all(ids)
    assert_equal 3, users.length

    users.each do |user|
      assert_kind_of Armagh::Authentication::User, user
    end

    assert_equal 'testuser1', users[0].username
    assert_equal 'testuser3', users[1].username
    assert_equal 'testuser4', users[2].username
  end

  def test_find_all_none
    ids = BSONSupport.random_object_ids(4)
    Armagh::Authentication::User.expects(:db_find).returns([])
    assert_empty Armagh::Authentication::User.find_all(ids)
  end

  def test_find_all_error
    e = Mongo::Error.new('error')
    Armagh::Authentication::User.expects(:db_find).raises(e)

    ids = BSONSupport.random_object_ids 4

    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::User.find_all(ids)}
  end

  def test_class_authenticate
    user = mock('user')
    user.expects(:authenticate).with('testpassword').returns(true)
    Armagh::Authentication::User.expects(:find_username).returns(user)
    result = Armagh::Authentication::User.authenticate('testuser', 'testpassword')
    assert_equal user, result
  end

  def test_class_authenticate_bad_password
    user = Armagh::Authentication::User.send(:new)
    user.stubs(:save)
    e = Armagh::Authentication::AuthenticationError.new('Account Locked')
    Armagh::Authentication::User.stubs(:find_username).returns(user)
    Armagh::Authentication::User::MAX_TRIES.times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for testuser.')) {
        Armagh::Authentication::User.authenticate('testuser', 'testpassword')
      }
    end

    assert_raise(e){Armagh::Authentication::User.authenticate('testuser', 'testpassword')}
  end

  def test_class_authenticate_bad_username
    Armagh::Authentication::User.stubs(:find_username).returns(nil)
    @dummy_user.stubs(:unlock)
    @dummy_user.stubs(:enable)
    @dummy_user.stubs(:authenticate).with('testpassword').returns(true)
    @dummy_user.expects(:lock)

    (Armagh::Authentication::User::MAX_TRIES).times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for testuser.')) {
        Armagh::Authentication::User.authenticate('testuser', 'testpassword')
      }
    end

    assert_equal({'testuser' => 3}, @dummy_user.db_doc['attempted_usernames'])
  end

  def test_class_authenticate_dummy_username
    @dummy_user.stubs(:authenticate).returns(true) # lets even pretend it's a valid password
    @dummy_user.stubs(:unlock)
    @dummy_user.stubs(:enable)
    @dummy_user.expects(:lock)
    Armagh::Authentication::User::MAX_TRIES.times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for __dummy_user__.')) {
        Armagh::Authentication::User.authenticate(Armagh::Authentication::User::DUMMY_USERNAME, 'testpassword')
      }
    end

    assert_equal({Armagh::Authentication::User::DUMMY_USERNAME => 3}, @dummy_user.db_doc['attempted_usernames'])
  end

  def test_authenticate
    user = create_user
    assert_nil user.last_login
    assert_true user.authenticate('testpassword')
    assert_in_delta Time.now, user.last_login, 1
  end

  def test_authenticate_ldap
    user = create_user
    user.directory = Armagh::Authentication::Directory::LDAP
    assert_false user.authenticate('testpassword')
    omit('ldap not implemented yet')
  end

  def test_authenticate_failure
    user = create_user
    assert_false user.authenticate('bad')
  end

  def test_authentication_lockout
    user = create_user
    assert_equal 0, user.auth_failures
    Armagh::Authentication::User::MAX_TRIES.times do |i|
      assert_false user.locked?
      user.authenticate('bad')
      assert_equal i+1, user.auth_failures
    end
    assert_true user.locked?
  end

  def test_authentication_lockout_permanent
    user = create_user
    user.mark_permanent

    Armagh::Authentication::User::MAX_TRIES.times do |i|
      assert_false user.locked?
      user.authenticate('bad')
      assert_equal i+1, user.auth_failures
    end
    assert_false user.locked?
  end

  def test_authentication_locked
    user = create_user
    assert_false user.locked?
    user.lock
    assert_true user.locked?

    e = Armagh::Authentication::AuthenticationError.new('Account Locked')
    assert_raise(e){user.authenticate('testpassword')}

    user.unlock
    assert_false user.locked?
    assert_nothing_raised{user.authenticate('testpassword')}
  end

  def test_authentication_disabled
    user = create_user
    assert_false user.disabled?
    user.disable
    assert_true user.disabled?

    e = Armagh::Authentication::AuthenticationError.new('Account Disabled')
    assert_raise(e){user.authenticate('testpassword')}

    user.enable
    assert_false user.disabled?
    assert_nothing_raised{user.authenticate('testpassword')}
  end

  def test_refresh
    user = create_user
    db_doc = user.db_doc.dup
    user.db_doc['some temp thing'] = 'blah'
    Armagh::Authentication::User.expects(:db_find_one).with('_id' => user.internal_id).returns db_doc
    assert_not_equal db_doc, user.db_doc
    user.refresh
    assert_equal db_doc, user.db_doc
  end

  def test_save_new
    id = '123'
    user = Armagh::Authentication::User.send(:new)
    Armagh::Authentication::User.expects(:db_create).with(user.db_doc).returns(id)
    assert_nil user.internal_id
    user.save
    assert_equal id, user.internal_id
    assert_in_delta(Time.now, user.created_timestamp, 1)
    assert_equal(user.updated_timestamp, user.created_timestamp)
  end

  def test_save_update
    id = '123'
    created_timestamp = Time.now - 10
    user = Armagh::Authentication::User.send(:new, {'_id' => id, 'created_timestamp' => created_timestamp, 'updated_timestamp' => created_timestamp})
    Armagh::Authentication::User.expects(:db_replace).with({'_id' => id}, user.db_doc).returns(id)
    assert_equal created_timestamp, user.created_timestamp
    assert_equal created_timestamp, user.updated_timestamp
    user.save
    assert_equal created_timestamp, user.created_timestamp
    assert_true created_timestamp < user.updated_timestamp
    assert_in_delta(Time.now, user.updated_timestamp, 1)
  end

  def test_save_no_timestamps
    id = '123'
    user = Armagh::Authentication::User.send(:new)
    Armagh::Authentication::User.expects(:db_create).with(user.db_doc).returns(id)
    user.save(update_timestamps: false)
    assert_nil user.updated_timestamp
    assert_nil user.created_timestamp

  end

  def test_assert_save_error
    e = Mongo::Error.new('error')
    user = Armagh::Authentication::User.send(:new)
    Armagh::Authentication::User.expects(:db_create).raises(e)

    assert_raise(Armagh::Connection::ConnectionError){user.save}
  end

  def test_delete
    id = '123'
    group = mock('group')
    user = create_user
    user.internal_id = id
    user.expects(:groups).returns([group])
    user.expects(:leave_group).with(group)
    Armagh::Authentication::User.expects(:db_delete).with('_id' => id)
    user.delete
  end

  def test_delete_error
    e = Mongo::Error.new('error')
    user = create_user
    Armagh::Authentication::User.expects(:db_delete).raises(e)
    assert_raise(Armagh::Connection::ConnectionError){user.delete}
  end

  def test_restrict_permanent
    user = create_user
    user.mark_permanent
    assert_raise(Armagh::Authentication::User::PermanentError){user.delete}
    assert_raise(Armagh::Authentication::User::PermanentError){user.lock}
    assert_raise(Armagh::Authentication::User::PermanentError){user.disable}
  end

  def test_username
    user = create_user
    original_username = user.username
    assert_not_equal'new_username', original_username
    user.username = 'new_username'
    assert_equal 'new_username', user.username

    user.username = 'UsErNaMe'
    assert_equal 'username', user.username

    e = Armagh::Authentication::User::UsernameError.new('Username can only contain alphabetic, numeric, and underscore characters.')
    assert_raise(e){user.username = 'bad username'}
    assert_raise(e){user.username = 'bad-username'}
    assert_raise(e){user.username = 'bad&username'}
  end

  def test_password
    user = create_user
    original_timestamp = user.password_timestamp
    original_hashed = user.hashed_password

    user.password = 'testpassword'

    assert_not_equal 'testpassword', user.hashed_password
    assert_not_equal original_hashed, user.hashed_password
    assert_not_equal original_timestamp, user.password_timestamp

    assert_in_delta Time.now, user.password_timestamp, 1
  end

  def test_password_external_dir
    user = create_user
    user.directory = Armagh::Authentication::Directory::LDAP
    e = Armagh::Authentication::User::DirectoryError.new 'No password stored for external users.'

    assert_raise(e){user.hashed_password}
    assert_raise(e){user.password = 'testpassword'}
    assert_raise(e){user.password_timestamp}
  end

  def test_password_reset
    user = create_user
    user.password = 'testpassword'
    old_hash = user.hashed_password
    assert_false user.required_password_reset?
    new_password = user.reset_password
    assert_not_equal(old_hash, user.hashed_password)
    assert_equal Armagh::Utils::Password::MIN_PWD_LENGTH, new_password.length
    assert_true user.required_password_reset?
  end

  def test_password_reset_external_dir
    user = create_user
    user.directory = Armagh::Authentication::Directory::LDAP
    e = Armagh::Authentication::User::DirectoryError.new 'No password stored for external users.'
    assert_raise(e){user.reset_password}
  end

  def test_name
    user = create_user
    name = 'some name'
    user.name = name
    assert_equal name, user.name
  end

  def test_email
    user = create_user
    email = 'test@user.com'
    user.email = email
    assert_equal email, user.email

    assert_raise(Armagh::Authentication::User::EmailError.new('Email format is invalid.')){user.email = 'invalid'}
  end

  def test_groups
    groups_collection = mock('groups')
    @connection.stubs(:[]).with('groups').returns(groups_collection)

    Armagh::Authentication::Group.any_instance.stubs(:save)
    group1 = Armagh::Authentication::Group.create(name: 'group_1', description: 'test group')
    group2 = Armagh::Authentication::Group.create(name: 'group_2', description: 'test group')
    group3 = Armagh::Authentication::Group.create(name: 'group_3', description: 'test group')
    group1.internal_id = 'id1'
    group2.internal_id = 'id2'
    group3.internal_id = 'id3'
    user = create_user

    group1.expects(:add_user).with(user, reciprocate: false)
    group2.expects(:add_user).with(user, reciprocate: false)
    group3.expects(:add_user).with(user, reciprocate: false)

    user.join_group group1
    user.join_group group2
    user.join_group group3

    result = [group1, group2, group3]
    args = [group1.internal_id, group2.internal_id, group3.internal_id]

    Armagh::Authentication::Group.expects(:find_all).with(args).returns result
    assert_equal result, user.groups

    assert_true user.member_of? group1
    assert_true user.member_of? group2
    assert_true user.member_of? group3

    assert_false user.member_of? Armagh::Authentication::Group.create(name: 'another_group', description: 'test group')

    group3.expects(:remove_user).with(user, reciprocate: false)
    user.leave_group group3

    assert_raise(Armagh::Authentication::User::GroupError.new("User 'testuser' is not a member of 'group_3'.")){user.leave_group group3}

    user.join_group group1

    Armagh::Authentication::Group.expects(:find_all).with(%w(id1 id2))
    user.groups
  end

  def test_roles
    user = create_user
    role1 = Armagh::Authentication::Role.send(:new, name: 'Role 1', description: 'some role', key: 'role_1')
    role2 = Armagh::Authentication::Role.send(:new, name: 'specific doc', description: 'specific doc access', key: 'some_doc', published_collection_role: true)

    assert_false user.has_role? role1
    assert_false user.has_role? role2
    assert_false user.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN

    user.add_role role1
    user.add_role role2

    assert_equal %w(role_1 some_doc), user.instance_variable_get(:@db_doc)['roles']
    Armagh::Authentication::Role.expects(:find).with(role1.key).returns(role1).at_least_once
    Armagh::Authentication::Role.expects(:find).with(role2.key).returns(role2).at_least_once

    assert_true user.has_role? role1
    assert_true user.has_role? role2
    assert_false user.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_false user.has_role? Armagh::Authentication::Role::USER

    user.remove_role role2
    assert_false user.has_role? role2

    user.add_role Armagh::Authentication::Role::USER
    Armagh::Authentication::Role.expects(:find).with(Armagh::Authentication::Role::USER.key).returns(Armagh::Authentication::Role::USER).at_least_once
    assert_true user.has_role? role2

    user.remove_all_roles
    assert_empty user.roles

    assert_raise(Armagh::Authentication::User::RoleError.new("User 'testuser' does not have a direct role of 'role_1'.")){user.remove_role(role1)}
  end

  def test_roles_of_groups
    groups_collection = mock('group_collection')
    @connection.stubs(:[]).with('groups').returns(groups_collection)
    user = create_user

    Armagh::Authentication::Group.any_instance.stubs(:save)
    group = Armagh::Authentication::Group.create(name: 'group_1', description: 'test group')

    group.stubs(:roles).returns [Armagh::Authentication::Role::USER_ADMIN]

    user.stubs(:groups).returns([group])

    group.expects(:add_user).with(user, reciprocate: false)
    user.join_group group

    assert_true user.has_role? Armagh::Authentication::Role::USER_ADMIN
    assert_false user.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
  end

  def test_permanent
    user = create_user
    assert_false user.permanent?
    user.mark_permanent
    assert_true user.permanent?
  end

  def test_equality
    user1 = create_user
    user1.internal_id = 'id1'
    user2 = create_user
    user2.internal_id = 'id2'

    assert_false user1 == user2
    assert_false user1.eql? user2
    assert_not_equal user1.hash, user2.hash

    user2.internal_id = user1.internal_id

    assert_true user1 == user2
    assert_true user1.eql? user2
    assert_equal user1.hash, user2.hash
  end

  def test_to_hash
    user1 = create_user
    hash = user1.db_doc.dup
    hash['disabled'] = false
    hash['locked'] = false
    hash['permanent'] = false
    assert_equal hash, user1.to_hash
  end

  def test_to_json
    user1 = create_user
    hash = user1.db_doc.dup
    hash['disabled'] = false
    hash['locked'] = false
    hash['permanent'] = false
    hash['id'] = hash['_id']
    hash.delete('_id')
    hash.delete('hashed_password')
    assert_equal(hash.to_json, user1.to_json)
  end
end