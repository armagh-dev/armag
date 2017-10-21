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
require_relative '../../helpers/armagh_test'

require_relative '../../../lib/armagh/status'
require_relative '../../../lib/armagh/connection'

require 'test/unit'
require 'mocha/test_unit'

class TestAgentStatus < Test::Unit::TestCase
  def setup
    @agent_status = create_agent_status
  end

  def create_agent_status
    Armagh::Status::AgentStatus.any_instance.stubs(:save)
    agent_status = Armagh::Status::AgentStatus.report(id: nil, hostname: nil, status: nil, task: nil, running_since: nil, idle_since: nil)
    agent_status
  end

  def test_default_collection
    assert_equal(Armagh::Connection.agent_status, Armagh::Status::AgentStatus.default_collection)
  end

  def test_report
    Armagh::Status::AgentStatus.any_instance.expects(:save)
    agent_status = Armagh::Status::AgentStatus.report(id: 'id', hostname: 'hostname', status: 'status', task: 'task', running_since: Time.at(0), idle_since: Time.at(10_000))
    assert_kind_of(Armagh::Status::AgentStatus, agent_status)

    assert_equal 'id', agent_status.internal_id
    assert_equal 'hostname', agent_status.hostname
    assert_equal 'status', agent_status.status
    assert_equal 'task', agent_status.task
    assert_equal Time.at(0), agent_status.running_since
    assert_equal Time.at(10_000), agent_status.idle_since
  end

  def test_delete
    id = 'id'
    Armagh::Status::AgentStatus.expects(:db_delete).with('_id' => id)
    Armagh::Status::AgentStatus.delete(id)

    e = RuntimeError.new('boom')
    Armagh::Status::AgentStatus.expects(:db_delete).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.delete(id)}
  end

  def test_find
    id = 'id'
    Armagh::Status::AgentStatus.expects(:db_find_one).with('_id' => id).returns({})
    result = Armagh::Status::AgentStatus.find(id)
    assert_kind_of(Armagh::Status::AgentStatus, result)

    e = RuntimeError.new('boom')
    Armagh::Status::AgentStatus.expects(:db_find_one).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.find(id)}

    expected = {'some' => 'value'}
    Armagh::Status::AgentStatus.expects(:db_find_one).with('_id' => id).returns(expected)
    result = Armagh::Status::AgentStatus.find(id, raw: true)
    assert_equal(expected, result)
  end

  def test_find_all
    Armagh::Status::AgentStatus.expects(:db_find).with({}).returns([{}, {}, {}])
    results = Armagh::Status::AgentStatus.find_all
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::AgentStatus, r)}

    e = RuntimeError.new('boom')
    Armagh::Status::AgentStatus.expects(:db_find).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.find_all}

    expected = [{'some' => 'value'}, {'another' => 'value'}]
    Armagh::Status::AgentStatus.expects(:db_find).returns(expected)
    result = Armagh::Status::AgentStatus.find_all(raw: true)
    assert_equal(expected, result)
  end

  def test_find_all_by_hostname
    hostname = 'name'
    Armagh::Status::AgentStatus.expects(:db_find).with({'hostname' => hostname}).returns([{}, {}, {}])
    results = Armagh::Status::AgentStatus.find_all_by_hostname(hostname)
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::AgentStatus, r)}

    e = RuntimeError.new('boom')
    Armagh::Status::AgentStatus.expects(:db_find).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.find_all_by_hostname(hostname)}

    expected = [{'some' => 'value'}, {'another' => 'value'}]
    Armagh::Status::AgentStatus.expects(:db_find).with({'hostname' => hostname}).returns(expected)
    results = Armagh::Status::AgentStatus.find_all_by_hostname(hostname, raw: true)
    assert_equal(expected, results)
  end

  def test_save
    Armagh::Status::AgentStatus.any_instance.unstub(:save)
    Armagh::Status::AgentStatus.expects(:db_replace).with({'_id' => @agent_status.internal_id}, @agent_status.db_doc)
    @agent_status.save

    e = RuntimeError.new('boom')
    Armagh::Status::AgentStatus.expects(:db_replace).raises(e)
    assert_raise(e){@agent_status.save}
  end

  def test_hostname
    hostname = 'hostname'
    @agent_status.hostname = hostname
    assert_equal hostname, @agent_status.hostname
  end

  def test_status
    status = '123'
    @agent_status.status = status
    assert_equal status, @agent_status.status
  end

  def test_task
    task = '123'
    @agent_status.task = task
    assert_equal task, @agent_status.task
  end

  def test_running_since
    running_since = Time.at(0)
    @agent_status.running_since = running_since
    assert_equal running_since, @agent_status.running_since
  end

  def test_idle_since
    idle_since = Time.at(0)
    @agent_status.idle_since = idle_since
    assert_equal idle_since, @agent_status.idle_since
  end

  def test_last_updated
    assert_kind_of(Time, @agent_status.last_updated)
    assert_in_delta(Time.now, @agent_status.last_updated, 1)
  end
end