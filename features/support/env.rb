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

require_relative '../../lib/connection'
require_relative '../../lib/version'

require_relative '../../test/helpers/coverage_helper'
require_relative '../../test/helpers/mongo_support'

require_relative 'launcher_support'
require_relative 'log_support'

require 'fileutils'
require 'test/unit/assertions'

FileUtils.mkdir_p LauncherSupport::DAEMON_DIR unless File.directory?(LauncherSupport::DAEMON_DIR)

def quiet_raise(msg)
  raise RuntimeError, msg, []
end

APP_VERSION = {'armagh' => Armagh::VERSION}

begin
  require 'armagh/standard_actions'
  APP_VERSION['standard'] = StandardActions::VERSION
rescue LoadError
  # Not a problem in test
rescue => e
  Armagh.send(:remove_const, :StandardActions)
end

require 'armagh/custom_actions'
APP_VERSION[Armagh::CustomActions::NAME] = Armagh::CustomActions::VERSION

quiet_raise "The custom actions gem that needs to be installed for testing is 'armagh_test-custom_actions'.  '#{Armagh::CustomActions::NAME}-custom_actions' was loaded instead." unless Armagh::CustomActions::NAME == 'armagh_test'

quiet_raise 'Mongo appears to be running already.  Please shut it down before trying to run these tests.' if Armagh::Connection.can_connect?


Before do
  LogSupport.delete_logs
end

After('@agent') do
  LauncherSupport.kill_launcher_processes
end

at_exit do
  begin
    MongoSupport.instance.clean_database
    MongoSupport.instance.stop_mongo
  rescue; end
end