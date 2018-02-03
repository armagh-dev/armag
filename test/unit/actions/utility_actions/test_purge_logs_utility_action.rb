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

require_relative '../../../helpers/coverage_helper'
require_relative '../../../helpers/workflow_generator_helper'
require_relative '../../../helpers/armagh_test'
require 'test/unit'
require 'mocha/test_unit'

require_relative '../../../../lib/armagh/actions/utility_actions/purge_logs_utility_action'

class TestPurgeLogUtilityAction < Test::Unit::TestCase
  include ArmaghTest

  def setup
    @config_store = []
    @caller = mock('caller')
    @logger = mock_logger

    @log_collection = mock('log_collection')
    @resource_log_collection = mock('resource_log_collection')
    Armagh::Connection.stubs(:all_log_collections).returns([@log_collection, @resource_log_collection])

    @config = Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.create_configuration(
      @config_store,
      'purgelogsutilityaction',
      Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.default_config_values,
      maintain_history: false
    )
    @purge_logs_action = Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.new(@caller, @logger, @config)
  end

  def expect_delete(collection)
    now = DateTime.now
    newest_debug = (now - @config.purge_logs.debug_age).to_time.utc
    newest_info= (now - @config.purge_logs.info_age).to_time.utc
    newest_warn = (now - @config.purge_logs.warn_age).to_time.utc
    newest_error = (now - @config.purge_logs.error_age).to_time.utc

    collection.expects(:delete_many).with do |args|
      levels = args.dig('level', '$in')
      case levels
      when %w(DEBUG)
        assert_in_delta(newest_debug, args.dig('timestamp', '$lte'), 1)
      when %w(ANY INFO)
        assert_in_delta(newest_info, args.dig('timestamp', '$lte'), 1)
      when %w(DEV_WARN OPS_WARN WARN)
        assert_in_delta(newest_warn, args.dig('timestamp', '$lte'), 1)
      when %w(FATAL DEV_ERROR OPS_ERROR ERROR)
        assert_in_delta(newest_error, args.dig('timestamp', '$lte'), 1)
      else
        assert false, "Unexpected level/$in argument #{levels}"
      end

      true
    end.times(4)
  end

  def test_run
    expect_delete @log_collection
    expect_delete @resource_log_collection

    @purge_logs_action.run
  end
end