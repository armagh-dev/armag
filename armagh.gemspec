# coding: utf-8
#
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

require_relative 'lib/version'

def self.get_build_version(version)
  if ENV['ARMAGH_PRODUCTION_RELEASE']
    version
  else
    revision = ENV['ARMAGH_INTEG_BUILD_REVISION']
    if revision.empty?
      "#{version}-dev"
    else
      "#{version}.#{revision}"
    end
  end
rescue
  "#{version}-dev"
end

Gem::Specification.new do |spec|
  spec.name          = 'armagh'
  spec.version       = get_build_version(Armagh::VERSION)
  spec.authors       = ['Noragh Analytics, Inc.']
  spec.email         = [ 'armagh@noragh.com' ]
  spec.summary       = ''
  spec.description   = ''
  spec.homepage      = ''
  spec.license       = 'Apache-2.0'

  spec.files         = Dir.glob('{bin,config,lib}/**/*') + %w(LICENSE README) 
  spec.executables   = Dir.glob('bin/*').collect{|f|f.sub('bin/','')}
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 2.3'

  # Caution: Since this is actually packaged as a gem, these just verify the required versions are installed.  The versions
  #            used at runtime may differ unless a version is explicitly set before the require.

  spec.add_runtime_dependency 'armagh-base-actions', '< 2.0'
  spec.add_runtime_dependency 'armagh-standard_actions', '< 2.0'
  spec.add_runtime_dependency 'exponential-backoff', '~> 0.0.2'
  spec.add_runtime_dependency 'sinatra', '~> 1.4'
  spec.add_runtime_dependency 'thin', '~> 1.6'
  spec.add_runtime_dependency 'oj', '~> 2.14'
  spec.add_runtime_dependency 'log4r', '~> 1.1'

  spec.add_development_dependency 'rake', '~> 11.0'
  spec.add_development_dependency 'noragh-gem-tasks'
  spec.add_development_dependency 'test-unit', '~> 3.1'
  spec.add_development_dependency 'cucumber', '~> 2.0'
  spec.add_development_dependency 'simplecov', '~> 0.10'
  spec.add_development_dependency 'simplecov-rcov', '~> 0.2'
  spec.add_development_dependency 'mocha', '~> 1.1'
  spec.add_development_dependency 'sys-proctable', '~> 0.9'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'fakefs', '~> 0.8'
  spec.add_development_dependency 'armagh_test-custom_actions', '< 2.0'
  spec.add_development_dependency 'rack-test', '~> 0.6'

end
