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

require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'

require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/logging'
require_relative '../../lib/armagh/actions/utility_actions/purge_logs_utility_action'

require 'test/unit'
require 'mocha/test_unit'

require 'mongo'

class TestPurgeLogsUtilityActionIntegration < Test::Unit::TestCase
  Struct.new('Event', :logger, :level, :time, :data)

  def setup
    @config_store = Armagh::Connection.config

    @config = Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.create_configuration(
      @config_store,
      'purgelogsutilityaction',
      Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.default_config_values,
      maintain_history: false
    )
    @purge_logs_action = Armagh::Actions::UtilityActions::PurgeLogsUtilityAction.new(@caller, @logger, @config)

    @appender = Armagh::Logging.mongo('test_appender')
  end

  def insert_logs
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::DEBUG, Time.now, 'DEBUG message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::INFO, Time.now, 'INFO message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::WARN, Time.now, 'WARN message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::ERROR, Time.now, 'ERROR message'))

    old_time = (DateTime.now - @config.purge_logs.info_age).to_time.utc - 1
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::DEBUG, old_time, 'old DEBUG message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::INFO, old_time, 'old INFO message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::WARN, old_time, 'old WARN message'))
    @appender.write(Struct::Event.new('test_logger', Armagh::Logging::ERROR, old_time, 'old ERROR message'))
  end

  def test_purge
    insert_logs
    original = Armagh::Connection.log.find({}).to_a
    @purge_logs_action.run

    deleted_levels = (original - Armagh::Connection.log.find({}).to_a).collect{|l| l['level']}
    assert_equal(%w(DEBUG INFO), deleted_levels)
  end
end
