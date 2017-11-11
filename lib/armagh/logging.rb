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

require 'logging'
require 'set'

require_relative 'logging/enhanced_exception'
require_relative 'logging/mongo_appender'

# Required for Sinatra/Rack
class ::Logging::Logger
  def <<(message)
    info message
  end

  alias_method :write, :<<
end

module Armagh
  module Logging
    FORMAT = '[%d] [%c]%X{action_workflow} %5l: %m\n' unless defined? FORMAT

    unless defined? LEVELS
      ::Logging.init :debug, :info, :warn, :ops_warn, :dev_warn, :error, :ops_error, :dev_error, :fatal, :any
      LEVELS = ::Logging::LNAMES.dup.freeze
      LEVELS.each_with_index {|lname, idx| const_set(lname, idx)}
      ALERT_LEVELS = %w{ WARN OPS_WARN DEV_WARN ERROR OPS_ERROR DEV_ERROR FATAL}.collect{ |lstr| LEVELS.index( lstr )}
    end

    def self.set_logger(name)
      ::Logging.logger[name]
    end

    def self.log_dir
      @log_dir
    end

    def self.set_details(workflow_name, action_name, action_supertype_name, doc_internal_id)
      ::Logging.mdc['workflow'] = workflow_name
      ::Logging.mdc['action'] = action_name
      ::Logging.mdc['action_supertype'] = action_supertype_name
      ::Logging.mdc['action_workflow'] = "[#{workflow_name}/#{action_name}]"
      ::Logging.mdc['document_internal_id'] = doc_internal_id
    end

    def self.clear_details
      ::Logging.mdc.delete 'workflow'
      ::Logging.mdc.delete 'action'
      ::Logging.mdc.delete 'action_supertype'
      ::Logging.mdc.delete 'action_workflow'
      ::Logging.mdc.delete 'document_internal_id'
    end

    def self.ops_error_exception(logger, exception, additional_info)
      logger.ops_error EnhancedException.new(additional_info, exception)
    end

    def self.dev_error_exception(logger, exception, additional_info)
      logger.dev_error EnhancedException.new(additional_info, exception)
    end

    def self.default_log_level(logger)
      temp_logger = set_logger(logger.name)
      LEVELS[temp_logger.level]
    end

    def self.set_level(logger, level_string)
      level_string = level_string.upcase
      level = level_string if LEVELS.include? level_string
      level ||= default_log_level(logger)

      unless logger.level == level
        logger.any "Changing log level to #{level}"
        logger.level = level
      end
    end

    def self.valid_log_levels
      LEVELS.collect { |level| level.downcase }
    end

    def self.valid_level?(candidate_level)
      valid_log_levels.include?(candidate_level.downcase)
    end

    def self.loggers(logger = ::Logging.logger.root)
      loggers = []
      loggers << logger
      ::Logging::Repository.instance.children(logger.name).each do |logger|
        loggers.concat loggers(logger)
      end

      loggers.uniq!
      loggers
    end

    def self.disable_mongo_log
      loggers.each do |logger|
        logger.appenders.each do |appender|
          logger.remove_appenders appender if appender.is_a? MongoAppender
        end
      end
    end

    def self.init_log_env
      init_log_dir
      init_loggers
    end

    private_class_method def self.init_log_dir
      @log_dir = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh'
      @log_dir.freeze
      unless File.directory?(@log_dir)
        begin
          FileUtils.mkdir_p @log_dir
        rescue Errno::EACCES
          $stderr.puts "Log directory '#{@log_dir}' does not exist and could not be created.  Please create the directory and grant the user running armagh full permissions."
          exit 1
        end
      end

      @log_dir = ENV['ARMAGH_APP_LOG'] || '/var/log/armagh'
      @app_logfile = File.join(@log_dir, 'agents.log')
      @app_admin_logfile = File.join(@log_dir, 'application_admin_api.log')
      @app_resource_admin_logfile = File.join(@log_dir, 'resource_admin_api.log')
      @mongo_logfile = File.join(@log_dir, 'mongo.log')
      @mongo_admin_logfile = File.join(@log_dir, 'mongo_admin.log')
      @gui_logfile = File.join(@log_dir, 'application_admin_gui.log')
    end

    private_class_method def self.init_loggers
      ::Logging.logger.root.level = :debug
      ::Logging.logger.root.add_appenders(::Logging.appenders.stdout(:layout => ::Logging.layouts.pattern(pattern: FORMAT)))

      app_logger = set_logger 'Armagh::Application'
      app_logger.add_appenders(::Logging.appenders.rolling_file(@app_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))
      app_logger.add_appenders(Armagh::Logging.mongo('mongo_app_log', {'alert_levels' => ALERT_LEVELS} ))

      app_admin_logger = set_logger 'Armagh::ApplicationAdminAPI'
      app_admin_logger.add_appenders(::Logging.appenders.rolling_file(@app_admin_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))
      app_admin_logger.add_appenders(Armagh::Logging.mongo('mongo_app_admin_log', {'resource_log' => true}))

      resource_admin_logger = set_logger'Armagh::ResourceAdminAPI'
      resource_admin_logger.add_appenders(::Logging.appenders.rolling_file(@app_resource_admin_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))
      resource_admin_logger.add_appenders(Armagh::Logging.mongo('mongo_resource_admin_log', {'resource_log' => true}))

      mongo_connection_logger = set_logger'Armagh::MongoConnection'
      mongo_connection_logger.level = :warn
      mongo_connection_logger.add_appenders(::Logging.appenders.rolling_file(@mongo_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))

      mongo_admin_connection_logger = set_logger'Armagh::MongoAdminConnection'
      mongo_admin_connection_logger.level = :warn
      mongo_admin_connection_logger.add_appenders(::Logging.appenders.rolling_file(@mongo_admin_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))

      gui_logger = set_logger 'Armagh::ApplicationAdminGUI'
      gui_logger.add_appenders(::Logging.appenders.rolling_file(@gui_logfile, {roll_by: 'date', layout: ::Logging.layouts.pattern(pattern: FORMAT)}))
    end
  end
end
