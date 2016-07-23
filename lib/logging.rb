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
#
# Caution: Since this script is distributed as part of a gem, when run from PATH it wont be executed as part of a bundle (even with require 'bundler/setup')
#            If any of the required need a specific version and there is a chance that multiple versions will be installed on the system, specify the gem version
#            as part of the requirement as well as in the gemspec.

require 'log4r'
require 'log4r/yamlconfigurator'
require 'log4r/outputter/datefileoutputter'

require_relative 'logging/enhanced_exception'
require_relative 'logging/hash_formatter'
require_relative 'logging/mongo_outputter'

module Armagh
  module Logging
    
    def self.init_log_env
      log_dir = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh'
      unless File.directory?(log_dir)
        begin
          FileUtils.mkdir_p log_dir
        rescue Errno::EACCES
          $stderr.puts "Log directory '#{log_dir}' does not exist and could not be created.  Please create the directory and grant the user running armagh full permissions."
          exit 1
        end
      end

      cfg = Log4r::YamlConfigurator
      cfg['LOG_DIR'] = log_dir
      cfg.load_yaml_file(File.join(__dir__, '..', 'config', 'log4r.yml'))
    end

    def self.ops_error_exception(logger, exception, additional_info)
      logger.ops_error EnhancedException.new(additional_info, exception)
    end

    def self.dev_error_exception(logger, exception, additional_info)
      logger.dev_error EnhancedException.new(additional_info, exception)
    end
  end
end