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
require_relative '../../../../helpers/armagh_test'

require 'test/unit'

require_relative '../../../../../lib/armagh/admin/application/www_root/models/user'

module Armagh
  module Admin
    module Application
      class TestUser < Test::Unit::TestCase

        def setup
          @user_hash = {
            id: '123',
            username: 'danchino',
            password: 'temppass!23',
            name: 'Danchino',
            roles: %w(application_admin resource_admin user_admin doc_user),
            groups: [],
            auth_failures: 0,
            directory: 'internal',
            password_timestamp: '2017-07-31 14:21:26 UTC',
            updated_timestamp: '2017-08-03 13:33:20 UTC',
            created_timestamp: '2017-07-31 14:21:26 UTC',
            last_login: '2017-08-03 13:33:52 UTC',
            required_password_reset: true,
            permanent: true,
            disabled: false,
            locked: false
          }
        end

        def test_create_user_object
          user = User.new(@user_hash)
          @user_hash.each do |field, value|
            assert_equal value, user.instance_variable_get("@#{field}")
          end
        end

      end
    end
  end
end
