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

require_relative '../helpers/coverage_helper'

require_relative '../../lib/utils/daemonizer'

require 'test/unit'
require 'mocha/test_unit'

require 'fileutils'

class TestDaemonizerIntegration < Test::Unit::TestCase
  def setup
    @script = File.join(__dir__, '..', 'fixtures', 'daemonize_script')
    @app_name = 'app_name'
    @work_dir = '/tmp/work_dir'

    @log_file = '/tmp/work_dir/app_name.log'
    @pid_file = '/tmp/work_dir/app_name.pid'
    @old_stdout = $stdout
    @stdout = StringIO.new
    $stdout = @stdout
    FileUtils.rm_rf @work_dir
  end

  def teardown
    $stdout = @old_stdout
    FileUtils.rm_rf @work_dir
  end

  def test_start
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    log = File.read(@log_file)
    assert_include(log, 'STDERR')
    assert_not_include(log, 'STDOUT')
    assert_true File.file?(@pid_file)
    pid = File.read(@pid_file).strip
    assert_include(@stdout.string, "Started app_name as PID #{pid}")
  end

  def test_start_lingering_pid
    FileUtils.mkdir_p @work_dir
    File.write(@pid_file, '99999999')
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    log = File.read(@log_file)
    assert_include(log, 'STDERR')
    assert_not_include(log, 'STDOUT')
    assert_true File.file?(@pid_file)
    pid = File.read(@pid_file).strip
    assert_includes(@stdout.string, "Started #{@app_name} as PID #{pid}")
    assert_includes(@stdout.string, 'A PID file exists for 99999999, which is not running.  Cleaning up')
  end

  def test_start_already_running
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    pid = File.read(@pid_file).strip
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "Started #{@app_name} as PID #{pid}")
    assert_includes(@stdout.string, "#{@app_name} is already running as PID #{pid}")
  end

  def test_stop
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    pid = File.read(@pid_file).strip
    ARGV.replace ['stop']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "Stopped #{@app_name} PID #{pid}")
  end

  def test_stop_not_running
    ARGV.replace ['stop']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "#{@app_name} was not running")
  end

  def test_restart
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    old_pid = File.read(@pid_file).strip

    ARGV.replace ['restart']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    new_pid = File.read(@pid_file).strip

    assert_includes(@stdout.string, "Stopped #{@app_name} PID #{old_pid}")
    assert_includes(@stdout.string, "Started #{@app_name} as PID #{new_pid}")
  end

  def test_restart_not_running
    ARGV.replace ['restart']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    pid = File.read(@pid_file).strip
    assert_includes(@stdout.string, "#{@app_name} was not running")
    assert_includes(@stdout.string, "Started #{@app_name} as PID #{pid}")
  end

  def test_status_running
    ARGV.replace ['start']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    pid = File.read(@pid_file).strip

    ARGV.replace ['status']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "#{@app_name} is running as PID #{pid}")
  end

  def test_status_dead
    FileUtils.mkdir_p @work_dir
    File.write(@pid_file, '99999999')
    ARGV.replace ['status']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "#{@app_name} terminated unexpectedly")
  end

  def test_status_none
    ARGV.replace ['status']
    Armagh::Utils::Daemonizer.run(@script, app_name: @app_name, work_dir: @work_dir)
    assert_includes(@stdout.string, "#{@app_name} is not running")
  end
end
