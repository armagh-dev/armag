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

require_relative '../../../lib/armagh/utils/daemonizer'

require 'armagh/logging'

require 'test/unit'
require 'mocha/test_unit'

require 'fakefs/safe'

module Armagh
  module Utils
    class Daemonizer
      def self.setup_test(suppress_stdout, log_file)
        @suppress_stdout = suppress_stdout
        @log_file = log_file
      end
    end
  end
end

class TestDaemonizer < Test::Unit::TestCase
  def setup
    @script = File.join(__dir__, '..', '..', 'fixtures', 'daemonize_script')
    @script_content = File.read(@script)
    @app_name = 'app_name'
    @work_dir = '/tmp/work_dir'
  end

  def test_run_no_script
    $stderr.expects(:puts).with("Script 'does_not_exist' does not exist.")
    assert_raise(SystemExit) { Armagh::Utils::Daemonizer.run('does_not_exist', app_name: @app_name, work_dir: @work_dir) }
  end

  def test_wrong_num_params
    ARGV.replace %w(start restart)
    $stderr.expects(:puts)
    assert_raise(SystemExit) { Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir) }
  end

  def test_start
    ARGV.replace(['start'])
    Armagh::Utils::Daemonizer.expects(:start)
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
  end

  def test_stop
    ARGV.replace(['stop'])
    Armagh::Utils::Daemonizer.expects(:stop)
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
  end

  def test_restart
    ARGV.replace(['restart'])
    Armagh::Utils::Daemonizer.expects(:restart)
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
  end

  def test_status
    ARGV.replace(['status'])
    Armagh::Utils::Daemonizer.expects(:status)
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
  end

  def test_unknown
    ARGV.replace(['something'])
    Armagh::Utils::Daemonizer.expects(:usage)
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
  end

  def test_suppress_stdout
    log_file = 'file'
    $stderr.expects(:reopen).with(log_file, 'a')
    $stdout.expects(:reopen).with('/dev/null')
    FakeFS do
      Armagh::Utils::Daemonizer.setup_test(true, log_file)
      Armagh::Utils::Daemonizer.send(:redirect_io)
    end
  end

  def test_no_suppress_stdout
    log_file = 'file'
    $stderr.expects(:reopen).with(log_file, 'a')
    $stdout.expects(:reopen).with($stderr)
    FakeFS do
      Armagh::Utils::Daemonizer.setup_test(false, log_file)
      Armagh::Utils::Daemonizer.send(:redirect_io)
    end
  end
end