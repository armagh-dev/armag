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

require_relative '../../../lib/armagh/status'
require_relative '../../../lib/armagh/connection'

require 'test/unit'
require 'mocha/test_unit'

class TestLauncherStatus < Test::Unit::TestCase
  def setup

    @launcher_status = create_launcher_status
  end

  def create_launcher_status
    @launcher_status_coll = mock
    Armagh::Connection.stubs( :launcher_status ).returns( @launcher_status_coll )
    @launcher_status_coll.stubs( :replace_one ).with(){ |qual, values, options|
      @values = values
      @values['_id'] = 'id'
    }.returns( @values )
    launcher_status = Armagh::Status::LauncherStatus.report(hostname: nil, status: nil, versions: nil, started: nil)
    launcher_status

  end

  def test_default_collection
    assert_equal(Armagh::Connection.launcher_status, Armagh::Status::LauncherStatus.default_collection)
  end

  def test_report
    launcher_status = Armagh::Status::LauncherStatus.report(hostname: 'hostname', status: 'status', versions: 'versions', started: Time.at(0).utc)
    assert_kind_of(Armagh::Status::LauncherStatus, launcher_status)

    assert_equal 'id', launcher_status.internal_id
    assert_equal 'hostname', launcher_status.hostname
    assert_equal 'status', launcher_status.status
    assert_equal 'versions', launcher_status.versions
    assert_equal Time.at(0).utc, launcher_status.started
  end


  def test_find_all
    @launcher_status_coll.expects(:find).with({}).returns([{}, {}, {}])
    results = Armagh::Status::LauncherStatus.find_all
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::LauncherStatus, r)}

    e = RuntimeError.new('boom')
    @launcher_status_coll.expects(:find).raises(e)
    assert_raise(e){Armagh::Status::LauncherStatus.find_all}

    expected = [{'internal_id'=> 'id1', 'status' => 'value'}, {'internal_id' => 'id2', 'status' => 'value'}]
    returned = expected.collect{ |h| h1=h.dup; h1['_id']=h1['internal_id']; h1.delete 'internal_id'; h1 }
    @launcher_status_coll.expects(:find).returns(returned)
    result = Armagh::Status::LauncherStatus.find_all( raw: true )
    assert_equal(expected, result)
  end

  def test_hostname
    hostname = 'hostname'
    @launcher_status.hostname = hostname
    assert_equal hostname, @launcher_status.hostname
  end

  def test_status
    status = '123'
    @launcher_status.status = status
    assert_equal status, @launcher_status.status
  end

  def test_versions
    versions = '123'
    @launcher_status.versions = versions
    assert_equal versions, @launcher_status.versions
  end
end