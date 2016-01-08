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
require 'mocha/test_unit'

require_relative '../../lib/logging/global_logger'

module ArmaghTest
  def self.mock_global_logger
    Armagh::Logging::GlobalLogger.any_instance.stubs(:add).returns(nil)
    Armagh::Logging::GlobalLogger.any_instance.stubs(:add_global).returns(nil)
  end
end
