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

require_relative '../../test_helpers/coverage_helper'
require_relative '../../../../lib/admin/resource/cluster_server'

require 'test/unit'
require 'mocha/test_unit'

class TestClusterServer < Test::Unit::TestCase

  def setup
    @cluster_server = Armagh::Admin::Resource::ClusterServer.new( '127.0.0.1' )
  end
  
  def test_profile
    profile = @cluster_server.profile
    assert_kind_of Numeric, profile[ 'cpus' ]
    assert_kind_of Numeric, profile[ 'ram' ]
    assert_kind_of Numeric, profile[ 'swap' ]
    assert_match /(Darwin|Linux)/, profile[ 'os' ], 'is not a recognized OS'
    assert_match /^ruby 2.3/i, profile[ 'ruby_v' ]
    assert_includes profile, 'armagh_v'
    assert_equal profile['disks'].keys.sort, [ 'ARMAGH_DATA', 'ARMAGH_DB_INDEX',  'ARMAGH_DB_JOURNAL', 'ARMAGH_DB_LOG' ]
    profile['disks'].each do | key, disk_data|
      assert_includes profile, 'dir'
      assert_includes profile, 'filesystem_name'
      assert_includes profile, 'filesystem_type'
      assert_kind_of Numeric, profile[ 'blocks' ]
      assert_kind_of Numeric, profile[ 'used' ]
      assert_kind_of Numeric, profile[ 'available' ]
      assert_kind_of Numeric, profile[ 'use_perc' ]
      assert_includes profile, 'mounted_on'
    end    
  end
  
end