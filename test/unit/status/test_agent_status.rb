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

class TestAgentStatus < Test::Unit::TestCase
  def setup
    @agent_status = create_agent_status
  end

  def create_agent_status
    @agent_status_coll = mock
    Armagh::Connection.stubs( :agent_status ).returns( @agent_status_coll )
    @agent_status_coll.stubs( :replace_one ).with(){ |qual, values, options|
      @values = values
      @values['_id'] = 'id'
    }.returns( @values )
    agent_status = Armagh::Status::AgentStatus.report(signature: nil, hostname: nil, status: nil, task: nil, running_since: nil, idle_since: nil)
    agent_status
  end

  def test_default_collection
    assert_equal(Armagh::Connection.agent_status, Armagh::Status::AgentStatus.default_collection)
  end

  def test_report
    agent_status = Armagh::Status::AgentStatus.report(signature: 'agent-007', hostname: 'hostname', status: 'status', task: 'task', running_since: Time.at(0), idle_since: Time.at(10_000))
    assert_kind_of(Armagh::Status::AgentStatus, agent_status)

    assert_equal 'agent-007', agent_status.signature
    assert_equal 'hostname', agent_status.hostname
    assert_equal 'status', agent_status.status
    assert_equal 'task', agent_status.task
    assert_equal Time.at(0), agent_status.running_since
    assert_equal Time.at(10_000), agent_status.idle_since
  end

  def test_find_all
    @agent_status_coll.expects(:find).with({}).returns([{}, {}, {}])
    results = Armagh::Status::AgentStatus.find_all
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::AgentStatus, r)}

    e = RuntimeError.new('boom')
    @agent_status_coll.expects(:find).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.find_all}

    expected = [{'internal_id'=> 'id1', 'status' => 'value'}, {'internal_id' => 'id2', 'task' => 'value'}]
    returned = expected.collect{ |h| h1=h.dup; h1['_id']=h1['internal_id']; h1.delete 'internal_id'; h1 }
    @agent_status_coll.expects(:find).returns(returned)
    result = Armagh::Status::AgentStatus.find_all( raw: true )
    assert_equal(expected, result)
  end

  def test_find_all_by_hostname
    hostname = 'name'
    @agent_status_coll.expects(:find).with({ 'hostname' => hostname }).returns([{}, {}, {}])
    results = Armagh::Status::AgentStatus.find_all_by_hostname(hostname)
    assert_equal 3, results.length
    results.each {|r| assert_kind_of(Armagh::Status::AgentStatus, r)}

    e = RuntimeError.new('boom')
    @agent_status_coll.expects(:find).raises(e)
    assert_raise(e){Armagh::Status::AgentStatus.find_all_by_hostname(hostname)}

    expected = [{'internal_id'=> 'id1', 'status' => 'value'}, {'internal_id' => 'id2', 'task' => 'value'}]
    returned = expected.collect{ |h| h1=h.dup; h1['_id']=h1['internal_id']; h1.delete 'internal_id'; h1 }
    @agent_status_coll.expects(:find).with({'hostname' => hostname }).returns(returned)
    results = Armagh::Status::AgentStatus.find_all_by_hostname(hostname, raw:true)
    assert_equal(expected, results)
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

end