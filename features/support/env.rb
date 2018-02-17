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

CONFIG_FILE = File.join(__dir__, '..', '..', 'test', 'armagh_env_test.json')
ENV['ARMAGH_CONFIG_FILE'] = CONFIG_FILE

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../../lib/armagh/connection'
require_relative '../../lib/armagh/version'

require_relative '../../test/helpers/coverage_helper'

require_relative '../../test/helpers/mongo_support'

require_relative 'launcher_support'
require_relative 'log_support'

require 'fileutils'

require 'test/unit/assertions'

require 'colored'

$stdout.sync = true
$stderr.sync = true

def quiet_raise(msg)
  raise RuntimeError, msg.red, []
end

APP_VERSION = {'armagh' => Armagh::VERSION}

begin
  require 'armagh/standard_actions'
  APP_VERSION['standard'] = Armagh::StandardActions::VERSION
rescue LoadError
  # Not a problem in test
rescue
  Armagh.send(:remove_const, :StandardActions)
end

require 'armagh/custom_actions'
APP_VERSION[Armagh::CustomActions::NAME] = Armagh::CustomActions::VERSION

quiet_raise "The custom actions gem that needs to be installed for testing is 'armagh_test-custom_actions'.  '#{Armagh::CustomActions::NAME}-custom_actions' was loaded instead." unless Armagh::CustomActions::NAME == 'armagh_test'

quiet_raise 'Mongo appears to be running already.  Please shut it down before trying to run these tests.' if Armagh::Connection.can_connect?

puts "Test logs are stored in #{LogSupport::LOG_DIR}"

LogSupport.delete_failure_logs

Before do
  LogSupport.delete_logs
end

After do |scenario|
  begin
    if scenario.failed?
      log_dir = File.join(LogSupport::FAILURE_LOGS, scenario.name)
      puts "Storing failed logs to #{log_dir}"
      FileUtils.mkdir_p log_dir
      FileUtils.cp_r(LogSupport::LOG_DIR, log_dir)
    end

    puts 'Stopping Armagh'
    LauncherSupport.kill_launcher_processes
  rescue => e
    $stderr.puts "Problem running scenario cleanup: #{e.message}\n#{e.backtrace.join("\n")}"
  end
end

After('@agent') do
end

at_exit do
  begin
    MongoSupport.instance.clean_database
    MongoSupport.instance.stop_mongo
  rescue; end

  index = ''
  LogSupport.each_failure_log do |log|
    if File.file? log
      path = log.sub("#{LogSupport::FAILURE_LOGS}/",'')
      index << "<a href='#{path}'>#{path}</a><br>\n"
    end
  end

  unless index.empty?
    file = File.join(LogSupport::FAILURE_LOGS, 'index.html')
    puts "Log Failure Index File: #{file}"
    File.write(file, index) unless index.empty?
  end

end