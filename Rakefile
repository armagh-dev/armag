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

require 'cucumber/rake/task'
require 'noragh/gem/tasks'
require 'rake/testtask'
require 'yard'
require 'fileutils'

desc 'Run tests'

task :ci => [:clean, :check_licenses, :yard]
task :ci_vm => [:ci, :test, :integration, :cucumber]
task :default => [:ci_vm]

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = "test/unit/**/test_*.rb"
  t.warning = false
end

Rake::TestTask.new(:integration) do |t|
  t.libs << 'integration'
  t.pattern = "test/integration/**/test_*.rb"
  t.warning = false
end

task :clean do
  rm_rf Dir.glob(%w(doc .yardoc coverage features/**/coverage test/**/coverage failure_logs))
end

task :check_licenses do
  sh "bundle exec license_finder --quiet --decisions_file licensing/approvals.yml"
end

Cucumber::Rake::Task.new

YARD::Rake::YardocTask.new
