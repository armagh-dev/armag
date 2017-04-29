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

require_relative '../../../lib/utils/password'

require 'test/unit'

class TestPassword < Test::Unit::TestCase
  def setup
    @common_pass = 'computer'
  end

  def test_hash
    password = 'test_password'
    assert_not_equal(password, Armagh::Utils::Password.hash(password))
    assert_not_equal(Armagh::Utils::Password.hash(password), Armagh::Utils::Password.hash(password)) # Unique Salt per save
    assert_true Armagh::Utils::Password.correct?(password, Armagh::Utils::Password.hash(password))
    assert_false Armagh::Utils::Password.correct?('wrong', Armagh::Utils::Password.hash(password))
  end

  def test_strength_too_short
    assert_raise(Armagh::Utils::Password::PasswordError, "Password must contain at least #{Armagh::Utils::Password::MIN_PWD_LENGTH} characters.") do
      Armagh::Utils::Password.verify_strength('a')
    end
  end

  def test_strength_strong
    assert_true Armagh::Utils::Password.verify_strength('*3hfuH#&H#jdf#*FJ*J#JKJD(J#FKEJ FKSDJIEJR#98*#HF383hfisfhoE#*hf')
  end

  def test_strength_common
    assert_raise(Armagh::Utils::Password::PasswordError, 'Password is a common password.') do
      Armagh::Utils::Password.verify_strength @common_pass
    end
  end

  def test_common
    assert_true Armagh::Utils::Password.common? @common_pass
  end

  def test_common_uncommon
    assert_false Armagh::Utils::Password.common? '#IJfjf93jfKFJLJ#'
  end

  def test_random_password
    pwd = Armagh::Utils::Password.random_password
    assert_equal Armagh::Utils::Password::MIN_PWD_LENGTH, pwd.length
    assert_not_equal(pwd, Armagh::Utils::Password.random_password)
  end
end
