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

require_relative '../../../../lib/environment'
Armagh::Environment.init

require_relative '../../../../lib/admin/resource/api'


require 'test/unit'
require 'mocha/test_unit'


class TestResourceApplicationAPI < Test::Unit::TestCase

  def setup
    @logger = mock
    @api = Armagh::Admin::Resource::API.instance
  end
  
  
  def test_implode_with_confirmation
    
    dropper = mock
    dropper.expects( :drop ).at_least_once
    
    Armagh::Connection.expects( :all_document_collections ).returns( [] )
    [ :documents, 
      :archive, 
      :failures,
      :config, 
      :users, 
      :status, 
      :log, 
      :resource_config, 
      :resource_log 
    ].each do |coll|
      Armagh::Connection.expects( coll ).returns( dropper )
    end
    Armagh::Connection.expects( :setup_indexes )
    
    assert_nothing_raised { 
      assert_true @api.implode( :confirm )
    }
  end
  
  def test_implode_no_confirmation
    
    assert_nothing_raised {
      assert_false @api.implode( nil )
    }
  end
end