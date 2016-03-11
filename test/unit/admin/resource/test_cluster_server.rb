# Copyright 2016 Noragh Analytics, Inc.
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

require_relative '../../../helpers/coverage_helper'
require_relative '../../../../lib/admin/resource/cluster_server'

require 'test/unit'
require 'mocha/test_unit'

class TestClusterServer < Test::Unit::TestCase

  def setup
    @logger = mock
    @cluster_server = Armagh::Admin::Resource::ClusterServer.new( '127.0.0.1', @logger)
  end

  # TODO unit test admin/resource/test_cluster_server: Enhance testing coverage
  
  def test_profile
    profile = @cluster_server.profile
    assert_kind_of Numeric, profile[ 'cpus' ]
    assert_kind_of Numeric, profile[ 'ram' ]
    assert_kind_of Numeric, profile[ 'swap' ]
    assert_match /(Darwin|Linux)/, profile[ 'os' ], 'is not a recognized OS'
    assert_match /^ruby 2.3/i, profile[ 'ruby_v' ]
    assert_includes profile, 'armagh_v'
    assert_equal profile['disks'].keys.sort, %w(base index journal log)

    profile['disks'].each do | key, disk_data|
      assert_true disk_data.has_key? 'dir'
      assert_true disk_data.has_key? 'filesystem_name'
      assert_true disk_data.has_key? 'filesystem_type'
      assert_kind_of Numeric, disk_data[ 'blocks' ]
      assert_kind_of Numeric, disk_data[ 'used' ]
      assert_kind_of Numeric, disk_data[ 'available' ]
      assert_kind_of Numeric, disk_data[ 'use_perc' ]
      assert_true disk_data.has_key? 'mounted_on'
    end
  end
  
end