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

module TestActionSupport
  def self.install_test_actions
    puts 'Installing Test Actions...'
    action_dir = File.join(__dir__, 'test-client_actions')
    puts `cd #{action_dir} && rake install:local`
  end

  def self.uninstall_test_actions
    puts 'Uninstalling Test Actions...'
    puts `gem uninstall test-client_actions -I -a`
  end
end