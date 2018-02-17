# Copyright 2018 Noragh Analytics, Inc.
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
# WARNING!!
#
# This file and the supporting ./armagh_env.json are set at the
# time of installation and cannot be changed.
#

require 'armagh/logging'

require_relative 'configuration/file_based_configuration'

require_relative 'authentication/user'
require_relative 'authentication/group'

module Armagh
  module Environment

    def self.init
      unless @initialized
        init_env_vars
        init_logging
        @initialized = true
      end
    end

    def self.log_dir
      init_logging
      @log_dir
    end

    def self.init_env_vars
        env_hash = Armagh::Configuration::FileBasedConfiguration.load('ENV')
        env_hash.each do |k, v|
          ENV[k] = v
        end
        @init_env_vars = true
    end

    def self.init_logging
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

      @app_logfile = File.join(@log_dir, 'agents.log')
      @app_admin_logfile = File.join(@log_dir, 'application_admin_api.log')
      @app_resource_admin_logfile = File.join(@log_dir, 'resource_admin_api.log')
      @mongo_logfile = File.join(@log_dir, 'mongo.log')
      @mongo_admin_logfile = File.join(@log_dir, 'mongo_admin.log')
      @gui_logfile = File.join(@log_dir, 'application_admin_gui.log')
    end

    private_class_method def self.init_loggers
      Logging.create_logger('Armagh::MongoConnection', [
        Logging.day_file(@mongo_logfile)
      ], level: :warn)

      Logging.create_logger('Armagh::MongoAdminConnection', [
        Logging.day_file(@mongo_admin_logfile)
      ], level: :warn)

      Logging.create_logger('Armagh::Application', [
        Logging.day_file(@app_logfile),
        Logging.mongo('mongo_app_log', Armagh::Connection.log)
      ])

      Logging.create_logger('Armagh::ApplicationAdminAP', [
        Logging.day_file(@app_admin_logfile),
        Logging.mongo('mongo_app_admin_log', Armagh::Connection.resource_log)
      ])

      Logging.create_logger('Armagh::ResourceAdminAPI', [
        Logging.day_file(@app_resource_admin_logfile),
        Logging.mongo('mongo_resource_admin_log', Armagh::Connection.resource_log)
      ])

      Logging.create_logger('Armagh::ApplicationAdminGUI', [
        Logging.day_file(@gui_logfile)
      ])
    end
  end
end

