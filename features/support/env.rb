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

require_relative '../../test/test_helpers/coverage_helper'
require_relative 'launcher_support'
require_relative 'log_support'
require_relative 'mongo_support'
require_relative 'test_action_support'

require 'fileutils'

FileUtils::mkdir_p LauncherSupport::DAEMON_DIR unless File.directory?(LauncherSupport::DAEMON_DIR)

TestActionSupport.install_test_actions

Before do
  LogSupport.delete_logs
end

After('@agent') do
  LauncherSupport.kill_launcher_processes
end

at_exit do
  MongoSupport.instance.clean_database
  MongoSupport.instance.stop_mongo
  TestActionSupport.uninstall_test_actions
end