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

require_relative 'logging/hash_formatter'
require_relative 'logging/mongo_outputter'

module Armagh
  module Logging
    LOG_DIR = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh'

    def self.init_log_env
      unless File.directory?(LOG_DIR)
        begin
          FileUtils.mkdir_p LOG_DIR
        rescue Errno::EACCES
          $stderr.puts "Log directory '#{LOG_DIR}' does not exist and could not be created.  Please create the directory and grant the user running armagh full permissions."
          exit 1
        end
      end

      cfg = Log4r::YamlConfigurator
      cfg['LOG_DIR'] = LOG_DIR
      cfg.load_yaml_file(File.join(__dir__, '..', 'config', 'log4r.yml'))
    end

    def self.error_exception(logger, exception, additional_info)
      logger.error create_log_exception(exception, additional_info)
    end

    def self.warn_exception(logger, exception, additional_info)
      logger.warn create_log_exception(exception, additional_info)
    end

    def self.info_exception(logger, exception, additional_info)
      logger.info create_log_exception(exception, additional_info)
    end

    def self.debug_exception(logger, exception, additional_info)
      logger.debug create_log_exception(exception, additional_info)
    end

    private
    def self.create_log_exception(exception, additional_info)
      log_exception = exception.class.new "#{additional_info}  Exception Details: #{exception.message}"
      log_exception.set_backtrace(exception.backtrace)
      log_exception
    end
  end
end