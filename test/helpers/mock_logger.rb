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

require 'test/unit'
require 'mocha'

module ArmaghTest
  def mock_logger
    logger = mock

    logger.expects(:debug).at_least(0)
    logger.expects(:info).at_least(0)
    logger.expects(:warn).at_least(0)
    logger.expects(:error).at_least(0)
    logger.expects(:any).at_least(0)
    logger.expects(:dev_warn).at_least(0)
    logger.expects(:ops_warn).at_least(0)
    logger.expects(:dev_error).at_least(0)
    logger.expects(:ops_error).at_least(0)
    logger.expects(:level).at_least(0)
    logger.expects(:levels).at_least(0).returns(Log4r::Logger.root.levels)

    Log4r::Logger.stubs(:[]).returns logger
    Log4r::Logger.stubs(:new).returns logger
    logger
  end
end