# coding: utf-8
#
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

require_relative 'lib/armagh/client_actions/constants'

Gem::Specification.new do |spec|
  spec.name          = 'test-client_actions'
  spec.version       = Armagh::ClientActions::VERSION
  spec.authors       = ['unknown']
  spec.email         = []
  spec.summary       = "Client actions for #{Armagh::ClientActions::NAME}"
  spec.description   = ''
  spec.homepage      = ''
  spec.license       = ''

  spec.files         = Dir.glob('lib/**/*') + %w(README)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'armagh-base-actions'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'mocha', '~> 1.1'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'test-unit'

end
