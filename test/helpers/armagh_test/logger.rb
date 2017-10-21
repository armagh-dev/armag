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

require 'test/unit'
require 'mocha/test_unit'
require_relative '../armagh_test'
require_relative '../../../lib/armagh/logging'

module ArmaghTest
  def mock_logger
    logger = mock('logger')

    logger.stubs(:debug)
    logger.stubs(:info)
    logger.stubs(:warn)
    logger.stubs(:error)
    logger.stubs(:any)
    logger.stubs(:dev_warn)
    logger.stubs(:ops_warn)
    logger.stubs(:dev_error)
    logger.stubs(:ops_error)
    logger.stubs(:level)
    logger.stubs(:debug?)
    logger.stubs(:info?)
    logger.stubs(:warn?)
    logger.stubs(:error?)
    logger.stubs(:name).returns('MockLogger')

    logger.stubs(:level=)
    Armagh::Logging.stubs(:set_logger).returns(logger)
    logger
  end
end