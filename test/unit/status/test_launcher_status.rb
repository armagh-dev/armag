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

require_relative '../../../lib/armagh/status'
require_relative '../../../lib/armagh/connection'

require 'test/unit'
require 'mocha/test_unit'

class TestLauncherStatus < Test::Unit::TestCase
  def setup

    @launcher_status = create_launcher_status
  end

  def create_launcher_status
    Armagh::Status::LauncherStatus.any_instance.stubs(:save)
    launcher_status = Armagh::Status::LauncherStatus.report(hostname: nil, status: nil, versions: nil, started: nil)
    launcher_status
  end

  def test_default_collection
    assert_equal(Armagh::Connection.launcher_status, Armagh::Status::LauncherStatus.default_collection)
  end

  def test_report
    Armagh::Status::LauncherStatus.any_instance.expects(:save)
    launcher_status = Armagh::Status::LauncherStatus.report(hostname: 'hostname', status: 'status', versions: 'versions', started: Time.at(0).utc)
    assert_kind_of(Armagh::Status::LauncherStatus, launcher_status)

    assert_equal 'hostname', launcher_status.internal_id
    assert_equal 'hostname', launcher_status.hostname
    assert_equal 'status', launcher_status.status
    assert_equal 'versions', launcher_status.versions
    assert_equal Time.at(0).utc, launcher_status.started
  end

  def test_delete
    hostname = 'hostname'
    Armagh::Status::LauncherStatus.expects(:db_delete).with('_id' => hostname)
    Armagh::Status::LauncherStatus.delete(hostname)

    e = RuntimeError.new('boom')
    Armagh::Status::LauncherStatus.expects(:db_delete).raises(e)
    assert_raise(e){Armagh::Status::LauncherStatus.delete(hostname)}
  end

  def test_find
    id = 'id'
    Armagh::Status::LauncherStatus.expects(:db_find_one).with('_id' => id).returns({})
    result = Armagh::Status::LauncherStatus.find(id)
    assert_kind_of(Armagh::Status::LauncherStatus, result)

    e = RuntimeError.new('boom')
    Armagh::Status::LauncherStatus.expects(:db_find_one).raises(e)
    assert_raise(e){Armagh::Status::LauncherStatus.find(id)}

    expected = {'some' => 'value'}
    Armagh::Status::LauncherStatus.expects(:db_find_one).with('_id' => id).returns(expected)
    result = Armagh::Status::LauncherStatus.find(id, raw: true)
    assert_equal(expected, result)
  end

  def test_find_all
    Armagh::Status::LauncherStatus.expects(:db_find).with({}).returns([{}, {}, {}])
    results = Armagh::Status::LauncherStatus.find_all
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::LauncherStatus, r)}

    e = RuntimeError.new('boom')
    Armagh::Status::LauncherStatus.expects(:db_find).raises(e)
    assert_raise(e){Armagh::Status::LauncherStatus.find_all}

    expected = [{'some' => 'value'}, {'another' => 'value'}]
    Armagh::Status::LauncherStatus.expects(:db_find).returns(expected)
    result = Armagh::Status::LauncherStatus.find_all(raw: true)
    assert_equal(expected, result)
  end

  def test_save
    Armagh::Status::LauncherStatus.any_instance.unstub(:save)
    Armagh::Status::LauncherStatus.expects(:db_replace).with({'_id' => @launcher_status.internal_id}, @launcher_status.db_doc)
    @launcher_status.save

    e = RuntimeError.new('boom')
    Armagh::Status::LauncherStatus.expects(:db_replace).raises(e)
    assert_raise(e){@launcher_status.save}
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

  def test_last_updated
    assert_kind_of(Time, @launcher_status.last_updated)
    assert_in_delta(Time.now, @launcher_status.last_updated, 1)
  end
end