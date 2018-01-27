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
    @config.expects(:refresh).twice
    @authentication_config.stubs(:min_password_length).returns(10).twice
    @users.expects(:find).with({ 'username' => 'admin' }).returns( mock(limit: []))
    @users.expects(:insert_one).returns(mock(inserted_ids:[ 'a1' ]))
    @users.expects(:find).with({ 'username' => '__dummy_user__' }).returns( mock(limit: []))
    @users.expects(:insert_one).returns(mock(inserted_ids:[ 'd1' ]))
    Armagh::Authentication::User.setup_default_users
  end

  def mock_mongo
    @connection = mock('connection')
    instance = mock
    instance.stubs(:connection).returns(@connection)

    @users = mock('users')
    @connection.stubs(:[]).with('users').returns(@users)
    @users.stubs(:replace_one)

    @groups = mock('groups')
    @connection.stubs(:[]).with('groups').returns(@groups)

    @config = mock('config')
    @authentication_config = mock('authentication_config')
    Armagh::Authentication.stubs(:config).returns(@config)
    @config.stubs(:authentication).returns(@authentication_config)

    @admin_user = mock('admin_user')
    @admin_user.stubs({remove_all_roles: nil, add_role: nil, save: nil})
    Armagh::Authentication::User.stubs(:find_username).with(Armagh::Authentication::User::ADMIN_USERNAME).returns(@admin_user)

    @dummy_user = mock('dummy_user')
    @dummy_user.stubs({save: nil, attempted_usernames: {}} )
    Armagh::Authentication::User.stubs(:find_username).with(Armagh::Authentication::User::DUMMY_USERNAME).returns(@dummy_user)

    @admin_connection = mock('admin_connection')
    admin_instance = mock
    admin_instance.stubs(:connection).returns(@admin_connection)

    Armagh::Connection::MongoConnection.stubs(:instance).returns(instance)
    Armagh::Connection::MongoAdminConnection.stubs(:instance).returns(admin_instance)
  end

  def create_user(id = 123, username: 'testuser')
    @users.expects(:insert_one).returns( mock( inserted_ids: [ id ] ))
    @config.expects(:refresh)
    @authentication_config.expects(:min_password_length).returns(10)
    user = Armagh::Authentication::User.create(username: username, password: 'testpassword', name: 'Test User', email: 'test@user.com')
    user
  end

  def create_group(id = 123, name=nil )
    group_name = name || "group_#{id}"
    @groups.expects(:insert_one).returns( mock(inserted_ids: [ id ]))
    Armagh::Authentication::Group.create(name: group_name, description: 'group description')
  end

  def test_default_collection
    Armagh::Connection.expects(:users).returns(@users)
    assert_equal @users, Armagh::Authentication::User.default_collection
  end

  def test_setup_default_users
    @config.expects(:refresh).twice
    @authentication_config.expects(:min_password_length).returns(10).twice

    Armagh::Authentication::User.expects(:find_by_username).with(Armagh::Authentication::User::ADMIN_USERNAME).returns(nil)
    @users.expects(:insert_one).with(has_entry('username', Armagh::Authentication::User::ADMIN_USERNAME)).returns(mock(inserted_ids:['admin']))

    Armagh::Authentication::User.expects(:find_by_username).with(Armagh::Authentication::User::DUMMY_USERNAME).returns(nil)
    @users.expects(:insert_one).with(has_entry('username', Armagh::Authentication::User::DUMMY_USERNAME)).returns(mock(inserted_ids:['dummy']))

    Armagh::Authentication::User.setup_default_users
  end

  def test_create
    @config.expects(:refresh).twice
    @authentication_config.expects(:min_password_length).returns(10).twice
    @users.expects(:insert_one).returns(mock(inserted_ids:[1]))
    @users.expects(:insert_one).returns(mock(inserted_ids:[2]))
    @users.expects(:insert_one).returns(mock(inserted_ids:[3]))

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
    existing_user = create_user
    existing_user.expects(:username=).with('existing_user')
    existing_user.expects(:password=).with('testpassword')
    existing_user.expects(:name=).with('test user')
    existing_user.expects(:email=).with('test@email.com')

    result = existing_user.update(username: 'existing_user', password: 'testpassword', name: 'test user', email: 'test@email.com')
    assert_equal existing_user, result
  end

  def test_find_by_username
    result = {'username' => 'testuser'}
    find_result = mock
    find_result.expects(:limit).returns([result]).twice
    @users.stubs(:find).with({'username' => 'testuser'}).returns(find_result).twice
    Armagh::Authentication::User.unstub(:find_by_username)
    assert_equal('testuser', Armagh::Authentication::User.find_by_username('testuser').username)
    assert_equal('testuser', Armagh::Authentication::User.find_by_username('TeStUser').username)
  end

  def test_find_by_username_none
    Armagh::Authentication::User.unstub(:find_by_username)
    @users.expects(:find).returns(mock(limit:[]))
    assert_nil Armagh::Authentication::User.find_by_username('username')
  end

  def test_find_username_error
    Armagh::Authentication::User.unstub(:find_by_username)
    e = Mongo::Error.new('error')
    @users.expects(:find).raises(e)
    assert_raise(Armagh::Connection::ConnectionError) {Armagh::Authentication::User.find_by_username('username')}
  end

   def test_find_all
    result = [ create_user(1, username:'testuser1'), nil, create_user(3, username:'testuser3'), create_user(4, username:'testuser4'), ]
    Armagh::Authentication::User.expects(:find_many).returns(result)
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
    result = [{'username' => 'testuser1'}, nil, {'username' => 'testuser3'}, {'username' => 'testuser4'} ]
    @users.expects(:find).with({'_id' => {'$in' => ids}}).returns(result)

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
    Armagh::Authentication::User.expects(:find_many).returns([])
    assert_empty Armagh::Authentication::User.find_all(ids)
  end

  def test_find_all_error
    e = Mongo::Error.new('error')
    @users.expects(:find).raises(e)

    ids = BSONSupport.random_object_ids 4

    assert_raise(Armagh::Connection::ConnectionError) {
      Armagh::Authentication::User.find_all(ids)}
  end

  def test_class_authenticate
    user = mock('user')
    user.expects(:authenticate).with('testpassword').returns(true)
    Armagh::Authentication::User.expects(:find_by_username).returns(user)
    result = Armagh::Authentication::User.authenticate('testuser', 'testpassword')
    assert_equal user, result
  end

  def test_class_authenticate_bad_password
    max_tries = 3
    @config.stubs(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(max_tries).times(3)

    user = Armagh::Authentication::User.send(:new)
    user.stubs(:save)
    e = Armagh::Authentication::AuthenticationError.new('Account Locked')
    Armagh::Authentication::User.stubs(:find_by_username).returns(user)
    max_tries.times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for testuser.')) {
        Armagh::Authentication::User.authenticate('testuser', 'testpassword')
      }
    end

    assert_raise(e){Armagh::Authentication::User.authenticate('testuser', 'testpassword')}
  end

  def test_class_authenticate_bad_username
    max_tries = 3
    @config.stubs(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(max_tries).times(6)

   Armagh::Authentication::User.stubs(:find_by_username).returns(nil)

    dummy_user = Armagh::Authentication::User.instance_variable_get( :@dummy_user )
    max_tries.times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for testuser.')) {
        Armagh::Authentication::User.authenticate('testuser', 'testpassword')
      }
    end

    assert_equal({'testuser' => 3}, dummy_user.attempted_usernames)
  end

  def test_class_authenticate_dummy_username
    max_tries = 3
    @config.stubs(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(max_tries).times(3)

    dummy_user = Armagh::Authentication::User.instance_variable_get( :@dummy_user )
    Armagh::Authentication::User.stubs( :find_by_username ).with('__dummy_user__' ).returns( dummy_user)
    dummy_user.stubs(:authenticate).returns(true) # lets even pretend it's a valid password
    max_tries.times do
      assert_raise(Armagh::Authentication::AuthenticationError.new('Authentication failed for __dummy_user__.')) {
        Armagh::Authentication::User.authenticate(Armagh::Authentication::User::DUMMY_USERNAME, 'testpassword')
      }
    end

    assert_equal({Armagh::Authentication::User::DUMMY_USERNAME => 3}, dummy_user.attempted_usernames)
  end

  def test_authenticate
    user = create_user
    assert_nil user.last_login
    @config.expects(:refresh)
    assert_true user.authenticate('testpassword')
    assert_in_delta Time.now, user.last_login, 1
  end

  def test_authenticate_ldap
    user = create_user
    user.directory = Armagh::Authentication::Directory::LDAP
    @config.expects(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(3)
    assert_false user.authenticate('testpassword')
    omit('ldap not implemented yet')
  end

  def test_authenticate_failure
    user = create_user
    @config.expects(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(3)
    assert_false user.authenticate('bad')
  end

  def test_authentication_lockout
    max_tries = 3
    @config.stubs(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(max_tries).times(3)

    user = create_user
    assert_equal 0, user.auth_failures
    max_tries.times do |i|
      assert_false user.locked_out?
      user.authenticate('bad')
      assert_equal i+1, user.auth_failures
    end
    assert_true user.locked_out?
  end

  def test_authentication_lockout_permanent
    max_tries = 3
    @config.stubs(:refresh)
    @authentication_config.expects(:max_login_attempts).returns(max_tries).times(3)

    user = create_user
    user.mark_permanent

    max_tries.times do |i|
      assert_false user.locked_out?
      user.authenticate('bad')
      assert_equal i+1, user.auth_failures
    end
    assert_false user.locked_out?
  end

  def test_authentication_locked
    user = create_user
    assert_false user.locked_out?
    user.lock_out
    assert_true user.locked_out?

    @config.expects(:refresh)
    e = Armagh::Authentication::AuthenticationError.new('Account Locked')
    assert_raise(e){user.authenticate('testpassword')}

    user.remove_lock_out
    assert_false user.locked_out?
    assert_nothing_raised{user.authenticate('testpassword')}
  end

  def test_authentication_disabled
    user = create_user
    assert_false user.disabled?
    user.disable
    assert_true user.disabled?

    e = Armagh::Authentication::AuthenticationError.new('Account Disabled')
    @config.expects(:refresh)
    assert_raise(e){user.authenticate('testpassword')}

    user.enable
    assert_false user.disabled?
    assert_nothing_raised{user.authenticate('testpassword')}
  end

  def test_refresh
    user = create_user
    user2 = create_user
    user2.username = 'fred'
    @users.expects(:find).with({'_id' => user.internal_id}).returns(mock(limit: [user.instance_variable_get(:@image)]))
    assert_not_same user2, user
    user2.refresh
    assert_equal user2, user
  end

  def test_save_new
    id = '123'
    user = Armagh::Authentication::User.send(:new)
    @users.expects(:insert_one).with(has_entries(user.instance_variable_get(:@image))).returns(mock(inserted_ids:[id]))
    assert_nil user.internal_id
    user.save
    assert_equal id, user.internal_id
    assert_in_delta(Time.now, user.created_timestamp, 1)
    assert_equal(user.updated_timestamp, user.created_timestamp)
  end

  def test_save_update
    id = '123'
    user = Armagh::Authentication::User.send(:new)
    @users.expects(:insert_one).with(has_entries(user.instance_variable_get(:@image))).returns(mock(inserted_ids:[id]))
    user.save
    sleep 1
    user.save
    assert user.updated_timestamp > user.created_timestamp
    assert_in_delta 1, user.updated_timestamp-user.created_timestamp, 0.5
  end

  def test_save_no_timestamps
    id = '123'
    user = Armagh::Authentication::User.send(:new)
    @users.expects(:insert_one).with(has_entries(user.instance_variable_get(:@image))).returns(mock(inserted_ids:[id]))
    assert_nil user.internal_id
    user.save(update_timestamps: false)
    assert_nil user.updated_timestamp
    assert_nil user.created_timestamp
  end

  def test_assert_save_error
    e = Mongo::Error.new('error')
    user = Armagh::Authentication::User.send(:new)
    @users.expects(:insert_one).raises(e)

    assert_raise(Armagh::Connection::ConnectionError){user.save}
  end

  def test_delete
    id = '123'
    group = mock('group')
    user = create_user(id)
    user.expects(:groups).returns([group])
    user.expects(:leave_group).with(group)
    @users.expects(:delete_one).with('_id' => id)
    user.delete
  end

  def test_delete_error
    e = Mongo::Error.new('error')
    user = create_user
    @users.expects(:delete_one).raises(e)
    assert_raise(Armagh::Connection::ConnectionError){user.delete}
  end

  def test_restrict_permanent
    user = create_user
    user.mark_permanent
    assert_raise(Armagh::Authentication::User::PermanentError){user.delete}
    assert_raise(Armagh::Authentication::User::PermanentError){user.lock_out}
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

    @config.expects(:refresh)
    @authentication_config.expects(:min_password_length).returns(10)
    user.password = 'test_password'

    assert_not_equal 'test_password', user.hashed_password
    assert_not_equal original_hashed, user.hashed_password
    assert_not_equal original_timestamp, user.password_timestamp

    assert_in_delta Time.now, user.password_timestamp, 1
  end

  def test_password_external_dir
    user = create_user
    user.directory = Armagh::Authentication::Directory::LDAP
    e = Armagh::Authentication::User::DirectoryError.new 'No password stored for external users.'

    assert_raise(e){user.hashed_password}
    assert_raise(e){user.password = 'test_password_external_dir'}
    assert_raise(e){user.password_timestamp}
  end

  def test_password_reset
    min_length = 10
    user = create_user

    @config.expects(:refresh).times(3)
    @authentication_config.expects(:min_password_length).returns(min_length).times(3)

    user.password = 'test_password_reset'
    old_hash = user.hashed_password
    assert_false user.required_password_reset?
    new_password = user.reset_password
    assert_not_equal(old_hash, user.hashed_password)
    assert_false Armagh::Utils::Password.correct?(new_password, old_hash)
    assert_equal min_length, new_password.length
    assert_true user.required_password_reset?
  end

  def test_password_reset_external_dir
    user = create_user

    @config.expects(:refresh)
    @authentication_config.expects(:min_password_length).returns(10)

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

    group1 = create_group('id1', 'group_1')
    group2 = create_group('id2', 'group_2')
    group3 = create_group('id3', 'group_3')
    user = create_user

    group1.expects(:add_user).with(user, reciprocate: false)
    group2.expects(:add_user).with(user, reciprocate: false)
    group3.expects(:add_user).with(user, reciprocate: false)

    @groups.stubs(:replace_one)

    user.join_group group1
    user.join_group group2
    user.join_group group3

    result = [group1, group2, group3]
    assert_equal result, user.groups

    assert_true user.member_of? group1
    assert_true user.member_of? group2
    assert_true user.member_of? group3

    other_group = create_group('other')
    assert_false user.member_of? other_group

    group3.expects(:remove_user).with(user, reciprocate: false)
    user.leave_group group3

    assert_raise(Armagh::Authentication::User::GroupError.new("User 'testuser' is not a member of 'group_3'.")){user.leave_group group3}

    user.join_group group1

    assert_equal [group1,group2], user.groups
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

    assert_equal ['Role 1','specific doc'], user.roles.collect{|r| r.name }

    assert_true user.has_role? role1
    assert_true user.has_role? role2
    assert_false user.has_role? Armagh::Authentication::Role::APPLICATION_ADMIN
    assert_false user.has_role? Armagh::Authentication::Role::USER

    user.remove_role role2
    assert_false user.has_role? role2

    user.add_role Armagh::Authentication::Role::USER
    assert_true user.has_role? role2

    user.remove_all_roles
    assert_empty user.roles
    assert_equal [], user.remove_role( role1)

  end

  def test_roles_of_groups
    user = create_user
    group = create_group
    group.stubs(:roles).returns [Armagh::Authentication::Role::USER_ADMIN]
    @groups.stubs(:replace_one)

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
    user1 = create_user( 'id1')
    user2 = create_user( 'id2' )
    user2a = create_user( 'id2' )

    assert_false user1 == user2
    assert_false user1.eql? user2
    assert_not_equal user1.hash, user2.hash


    assert_true user2 == user2a
    assert_true user2.eql? user2a
    assert_equal user2.hash, user2a.hash
  end

  def test_to_hash
    user1 = create_user
    expected_result = {
        "directory"=>"internal",
        "username"=>"testuser",
        "name"=>"Test User",
        "email"=>"test@user.com",
        "disabled"=>false,
        "auth_failures"=>0,
        "locked_out"=>false,
        "groups"=>[],
        "roles"=>[],
        "internal_id"=>123}

    residual = user1.to_hash.delete_if{ |k| /timestamp/ =~ k || k == 'hashed_password' }
    assert_equal expected_result, residual
  end

  def test_to_json
    user1 = create_user
    expected_result = {
        "directory"=>"internal",
        "username"=>"testuser",
        "name"=>"Test User",
        "email"=>"test@user.com",
        "disabled"=>false,
        "auth_failures"=>0,
        "locked_out"=>false,
        "groups"=>[],
        "roles"=>[],
        "internal_id"=>123}

    residual = JSON.parse( user1.to_json ).delete_if{ |k| /timestamp/ =~ k || k == 'hashed_password' }
    assert_equal expected_result, residual
  end
end