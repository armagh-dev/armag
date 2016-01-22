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

require 'fileutils'

module LogSupport

  LOG_DIR = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh' unless defined? LOG_DIR

  def self.each_log
    Dir.glob(File.join(LOG_DIR, '*.log')).each do |log_file|
      yield log_file
    end
  end

  def self.empty_logs
    each_log{|log| File.truncate(log, 0)}
  end

  def self.delete_logs
    FileUtils.mkdir_p  LOG_DIR
    raise "Invalid permissions on #{LOG_DIR}" unless File.readable?(LOG_DIR) && File.writable?(LOG_DIR)
    each_log{|log| File.delete(log)}
  end
end


