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

require_relative '../../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../../lib/armagh/logging/alert'

require 'test/unit'
require 'mocha/test_unit'

class TestAlerting < Test::Unit::TestCase

  def setup
    Armagh::Connection.stubs(log: mock)
  end

  def expect_db_call_for_get_counts( match_filter, return_counts )
    Armagh::Connection.log.expects(:aggregate).with(
      [ { '$match' => match_filter },
        { '$group' => { '_id' => '$level', 'count' => { '$sum' => 1}}}]
    ).returns(return_counts)
  end

  def expect_db_call_for_get( filter, returned_log_entries)
    Armagh::Connection.log.expects(:find).with(filter).returns(returned_log_entries)
  end

  def expect_db_call_for_clear( filter )
    Armagh::Connection.log.expects(:update_one).with( filter, {'$unset'=>{'alert' => 1 }})
  end

  def test_get_counts

    expect_db_call_for_get_counts(
        { 'alert'=>true },
        [ { '_id' => 'OPS_WARN', 'count' => 2},
          { '_id' => 'DEV_ERROR', 'count' => 5 },
          { '_id' => 'DEV_WARN', 'count' => 1}
        ])
    expected_result = { 'warn' => 3, 'error' => 5, 'fatal' => 0}
    actual_result = Armagh::Logging::Alert.get_counts( )
    assert_equal expected_result, actual_result

    expect_db_call_for_get_counts(
        { 'alert'=>true, 'workflow' => 'wf' },
        [ { '_id' => 'OPS_ERROR', 'count' => 6},
          { '_id' => 'FATAL', 'count' => 1 }
        ])
    expected_result = { 'warn' => 0, 'error' => 6, 'fatal' => 1}
    actual_result = Armagh::Logging::Alert.get_counts( workflow: 'wf' )
    assert_equal expected_result, actual_result

    expect_db_call_for_get_counts(
        { 'alert'=>true, 'action' => 'fred' },
        [ { '_id' => 'OPS_WARN', 'count' => 2},
          { '_id' => 'ERROR', 'count' => 1 }
        ])
    expected_result = { 'warn' => 2, 'error' => 1, 'fatal' => 0}
    actual_result = Armagh::Logging::Alert.get_counts( action: 'fred' )
    assert_equal expected_result, actual_result

  end

  def test_get

    t = Time.now
    returned_log_record = {
        '_id' => '123',
        'level' => 'ERROR',
        'timestamp' => t,
        'workflow' => 'something',
        'action' => 'fred',
        'message' => 'oops',
        'exception' => { 'message' => 'detail'}}
    expected_alert = {
        '_id' => '123',
        'level' => 'ERROR',
        'timestamp' => t,
        'workflow' => 'something',
        'action' => 'fred',
        'full_message' => 'oops: detail'

    }

    expect_db_call_for_get(
        { 'alert' => true },
        [ returned_log_record ]
    )
    actual_result = Armagh::Logging::Alert.get
    assert_equal [ expected_alert ], actual_result

    expect_db_call_for_get(
        { 'alert' => true, 'workflow' => 'something' },
        [ returned_log_record ]
    )
    actual_result = Armagh::Logging::Alert.get(workflow:'something')
    assert_equal [ expected_alert ], actual_result

    expect_db_call_for_get(
        { 'alert' => true, 'action' => 'fred' },
        [ returned_log_record ]
    )
    actual_result = Armagh::Logging::Alert.get(action:'fred')
    assert_equal [ expected_alert ], actual_result

  end

  def test_clear

    expect_db_call_for_clear( { 'alert' => true, '_id' => '123'})
    Armagh::Logging::Alert.clear( internal_id: '123' )

    expect_db_call_for_clear( { 'alert' => true, 'workflow' => 'something' })
    Armagh::Logging::Alert.clear( workflow: 'something' )

    expect_db_call_for_clear( { 'alert' => true, 'action' => 'fred' })
    Armagh::Logging::Alert.clear( action: 'fred' )

    assert_raises Armagh::Logging::AlertClearingError do
      Armagh::Logging::Alert.clear( )
    end

    assert_raises Armagh::Logging::AlertClearingError do
      Armagh::Logging::Alert.clear(internal_id:'123', workflow: 'something' )
    end
  end
end