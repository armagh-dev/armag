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
#
# Caution: Since this script is distributed as part of a gem, when run from PATH it wont be executed as part of a bundle (even with require 'bundler/setup')
#            If any of the required need a specific version and there is a chance that multiple versions will be installed on the system, specify the gem version
#            as part of the requirement as well as in the gemspec.

require 'log4r'
require 'log4r/yamlconfigurator'
require 'log4r/outputter/datefileoutputter'
require 'set'

require_relative 'logging/enhanced_exception'
require_relative 'logging/hash_formatter'
require_relative 'logging/mongo_outputter'

# Required for Sinatra/Rack
class Log4r::Logger
  def <<(message)
    info(message)
  end
end

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
      cfg.load_yaml_file(File.join(__dir__, '..', '..', 'config', 'log4r.yml'))
    end

    def self.set_logger(name)
      Log4r::Logger[name] || Log4r::Logger.new(name)
    end

    def self.ops_error_exception(logger, exception, additional_info)
      logger.ops_error EnhancedException.new(additional_info, exception)
    end

    def self.dev_error_exception(logger, exception, additional_info)
      logger.dev_error EnhancedException.new(additional_info, exception)
    end

    def self.default_log_level(logger)
      temp_logger = set_logger(logger.name)
      temp_logger.levels[temp_logger.level].downcase
    end

    def self.set_level(logger, level_string)
      level = logger.levels.index { |ls| ls == level_string.upcase } || default_log_level(logger)

      unless logger.level == level
        logger.any "Changing log level to #{logger.levels[level]}"
        logger.level = level
      end
    end

    def self.valid_log_levels
      Log4r::Logger.new('temp').levels.collect { |level| level.downcase }
    end

    def self.valid_level?(candidate_level)
      valid_log_levels.include?(candidate_level.downcase)
    end

    def self.disable_mongo_log
      Log4r::Logger.each_logger do |logger|
        logger.outputters.each do |outputter|
          logger.remove(outputter.name) if outputter.is_a? Log4r::MongoOutputter
        end
      end
    end
  end
end