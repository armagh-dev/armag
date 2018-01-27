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
require_relative '../../../lib/armagh/utils/password'

require 'test/unit'
require 'mocha/test_unit'

class TestPassword < Test::Unit::TestCase
  def setup
    @common_pass = 'computer'
    @password_length = 10

    @config = mock('config')
    @authentication_config = mock('authentication_config')
    Armagh::Authentication.stubs(:config).returns(@config)
    @config.stubs(:authentication).returns(@authentication_config)
    @authentication_config.stubs(:min_password_length).returns(@password_length)
  end

  def test_hash
    password = 'test_password'
    assert_not_equal(password, Armagh::Utils::Password.hash(password))
    assert_not_equal(Armagh::Utils::Password.hash(password), Armagh::Utils::Password.hash(password)) # Unique Salt per save
    assert_true Armagh::Utils::Password.correct?(password, Armagh::Utils::Password.hash(password))
    assert_false Armagh::Utils::Password.correct?('wrong', Armagh::Utils::Password.hash(password))
  end

  def test_strength_not_string
    @config.expects(:refresh)
    assert_raise(Armagh::Utils::Password::PasswordError.new('Password must be a string.')) do
      Armagh::Utils::Password.verify_strength(123)
    end
  end

  def test_strength_too_short
    @config.expects(:refresh)
    assert_raise(Armagh::Utils::Password::PasswordError.new("Password must contain at least #{@password_length} characters.")) do
      Armagh::Utils::Password.verify_strength('a')
    end
  end

  def test_strength_strong
    @config.expects(:refresh)
    assert_true Armagh::Utils::Password.verify_strength('*3hfuH#&H#jdf#*FJ*J#JKJD(J#FKEJ FKSDJIEJR#98*#HF383hfisfhoE#*hf')
  end

  def test_strength_common
    @config.expects(:refresh)
    @authentication_config.stubs(:min_password_length).returns(1)
    assert_raise(Armagh::Utils::Password::PasswordError.new('Password is a common password.')) do
      Armagh::Utils::Password.verify_strength(@common_pass)
    end
  end

  def test_strength_reuse
    @config.expects(:refresh)
    password = 'Jfij3fj8jf83hsjdfhksf83h#&&HDH@jh@'
    hash = Armagh::Utils::Password.hash(password)
    assert_raise(Armagh::Utils::Password::PasswordError.new('Password cannot be the same as the previous password.')) do
      Armagh::Utils::Password.verify_strength password, hash
    end
  end

  def test_strength_no_reuse
    @config.expects(:refresh)
    hash = Armagh::Utils::Password.hash('old_password_#&&HDH@jh@')
    assert_true Armagh::Utils::Password.verify_strength 'new_password_#&&HDH@jh@', hash
  end

  def test_common
    assert_true Armagh::Utils::Password.common? @common_pass
  end

  def test_common_uncommon
    assert_false Armagh::Utils::Password.common? '#IJfjf93jfKFJLJ#'
  end

  def test_random_password
    @password_length = 10
    @config.expects(:refresh).twice
    pwd = Armagh::Utils::Password.random_password
    assert_equal @password_length, pwd.length
    assert_not_equal(pwd, Armagh::Utils::Password.random_password)
  end
end
