#!/usr/bin/env ruby
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
#
# Caution: Since this script is distributed as part of a gem, when run from PATH it wont be executed as part of a bundle (even with require 'bundler/setup')
#            If any of the required need a specific version and there is a chance that multiple versions will be installed on the system, specify the gem version
#            as part of the requirement as well as in the gemspec.

require 'drb/unix'
require 'fileutils'
require 'socket'

require 'log4r'
require 'configh'

require_relative '../environment'
Armagh::Environment.init

require_relative '../agent/agent'
require_relative '../agent/agent_status'
require_relative '../action/workflow'
require_relative '../action/gem_manager'
require_relative '../utils/collection_trigger'
require_relative '../connection'
require_relative '../ipc'
require_relative '../logging'
require_relative '../version'

module Armagh
  
  class LauncherConfigError < StandardError; end
  class AgentConfigError    < StandardError; end
  class WorkflowConfigError < StandardError; end
  
  class Launcher
    include Configh::Configurable

    define_parameter name: "num_agents",        description: "Number of agents",                      type: 'positive_integer', required: true, default: 1,      group: 'launcher'
    define_parameter name: "update_frequency",  description:  "Configuration refresh rate (seconds)", type: 'positive_integer', required: true, default: 60,     group: 'launcher'
    define_parameter name: "checkin_frequency", description: "Status update rate (seconds)",          type: 'positive_integer', required: true, default: 60,     group: 'launcher'
    define_parameter name: "log_level",         description: "Log level",                             type: 'populated_string', required: true, default: 'info', group: 'launcher'
    define_group_validation_callback callback_class: Launcher, callback_method: :report_validation_errors

    TERM_SIGNALS = [:INT, :QUIT, :TERM]

    def Launcher.report_validation_errors( candidate_config )
      errors = nil
      unless Logging.valid_level?( candidate_config.launcher.log_level)
        errors = "Log level must be one of #{ Logging.valid_log_levels.join(', ')}"
      end
      errors
    end

    def Launcher.config_name( launcher_name = 'default' )
      [ Connection.ip, launcher_name ].join("_")
    end

    def initialize( launcher_name = 'default' )
      @logger = Logging.set_logger('Armagh::Application::Launcher')

      unless Connection.can_connect?
        Logging.disable_mongo_log
        @logger.error "Unable to establish connection to the MongoConnection database configured in '#{Configuration::FileBasedConfiguration.filepath}'.  Ensure the database is running."
        exit 1
      end
      
      bind_ip = Connection.ip
      launcher_config_name = [ bind_ip, launcher_name ].join('_')
      
      begin
        @config = Launcher.find_or_create_configuration( Connection.config, launcher_config_name, values_for_create: {}, :maintain_history => true )
      rescue Configh::ConfigInitError, Configh::ConfigValidationError => e
        @logger.dev_error LauncherConfigError
      end
      
      @logger.any "Using Launcher Config: #{launcher_config_name}"
      Logging.set_level(@logger, @config.launcher.log_level)

      @versions = get_versions
      Document.version['armagh'] = @versions[ 'armagh' ]
      @versions[ 'actions' ].each do |package, version|
        Document.version[ package ] = version
      end
      
      begin
        @agent_config = Agent.find_or_create_configuration( Connection.config, 'default', values_for_create: {}, :maintain_history => true )
      rescue Configh::ConfigInitError, Configh::ConfigValidationError => e
        @logger.dev_error AgentConfigError
      end
      
      begin
        @workflow = Actions::Workflow.new( @logger, Connection.config )
        @logger.any 'workflow init successful'
      rescue Configh::ConfigInitError, Configh::ConfigValidationError => e
        @logger.any 'workflow init failed'
        @logger.dev_error WorkflowConfigError
      end
      
      @collection_trigger = Utils::CollectionTrigger.new(@workflow)
      Logging.set_level(@collection_trigger.logger,  @config.launcher.log_level)

      @hostname = Socket.gethostname
      @agents = {}
      @running = false
    rescue => e
      Logging.dev_error_exception(@logger, e, 'Error initializing launcher')
      exit 1
    end

    def reconcile_agents
      reported_agents = AgentStatus.get_statuses(@agent_status).keys
      running_agents = @agents.values.collect{|a| a.uuid}

      reported_not_running = reported_agents - running_agents
      running_not_reported = running_agents - reported_agents

      reported_not_running.each {|id| @agent_status.remove_agent(id) }

      @logger.error "The following agents are reported but not running: #{reported_not_running.join(', ')}" unless reported_not_running.empty?
      @logger.error "The following agents are running but not reporting: #{running_not_reported.join(', ')}" unless running_not_reported.empty?
    end

    def checkin(status)
      checkin = {
          'versions' => @versions,
          'last_update' => Time.now,
          'status' => status,
      }

      checkin['agents'] = AgentStatus.get_statuses(@agent_status) if @running

      @logger.debug "Checking In: #{checkin}"
      Connection.status.find('_id' => @hostname).replace_one(checkin, {upsert: true})

      @last_checkin = Time.now
    rescue => e
      raise Connection.convert_mongo_exception(e)
    end

    def apply_config
      Logging.set_level(@logger, @config.launcher.log_level)
      Logging.set_level(@collection_trigger.logger, @config.launcher.log_level)
      set_num_agents(@config.launcher.num_agents)
      @logger.debug "Updated configuration to log level #{ @config.launcher.log_level.upcase }, num agents #{ @config.launcher.num_agents }"
    end

    def set_num_agents(num_agents)
      kill_all_agents
      @logger.any "Setting number of agents to #{num_agents}"
      launch_agents(num_agents)
    end

    def launch_agents(num_agents)
      num_agents.times do
        start_agent_in_process
      end
      sleep 1
    end

    def kill_all_agents(signal = :SIGINT)
      kill_agents(@agents.length, signal)
    end

    def kill_agents(num_agents, signal = :SIGINT)
      num_agents.times do
        killed_pid = stop_agent(signal)
        agent_id = @agents[killed_pid].uuid
        @agents.delete killed_pid
        @agent_status.remove_agent(agent_id)
      end
    end

    def recover_dead_agents
      dead_agents = []
      @agents.each do |pid, agent|
        wait_pid, status = Process.waitpid2(pid, Process::WNOHANG)
        if wait_pid
          @logger.error "Agent #{agent.uuid} (PID: #{pid}) terminated with exit code #{status}. Restarting it"
          dead_agents << agent
          agent_id = @agents[pid].uuid
          @agents.delete(pid)
          @agent_status.remove_agent(agent_id)
        end
      end

      dead_agents.each do |agent|
        start_agent_in_process(agent)
      end
    end

    def start_agent_in_process(agent=nil)
      agent ||= Agent.new( @agent_config, @workflow )

      pid = Process.fork do
        Process.setproctitle("armagh-#{agent.uuid}")
        TERM_SIGNALS.each do |signal|
          trap(signal) {agent.stop}
        end
        begin
          agent.start
          @logger.info "Agent #{agent.uuid} terminated"
        rescue => e
          Logging.dev_error_exception(@logger, e, "Could not start agent #{agent.uuid}")
        end
      end

      @agents[pid] = agent
    end

    def stop_agent(signal)
      pid = @agents.keys.first
      Process.kill(signal, pid)
      begin
        pid = Process.wait
      rescue Errno::ECHILD; end
      pid
    end

    def shutdown(signal)
      Thread.new{ @logger.any "Received #{signal}.  Shutting down once agents finish" }.join
      @running = false
      @collection_trigger.stop
      Thread.new{kill_all_agents(signal)}.join
    end

    def refresh_config
      # Explicitly call them all out to refresh all if there any any to refresh
      config = @config.refresh
      agent_config = @agent_config.refresh
      workflow = @workflow.refresh

      if config || agent_config || workflow
        @logger.any 'Configuration change detected.  Restarting agents...'

        @logger.debug {
          changed_configs = []
          changed_configs << 'launcher' if config
          changed_configs << 'agent' if agent_config
          changed_configs << 'workflow' if workflow
          "Triggered by configuration changes to #{changed_configs.join(', ')}"
        }

        kill_all_agents
        apply_config
      else
        @logger.debug 'No configuration updates to apply.'
      end
    end

    def get_versions
 
     versions = {
        'armagh'  => VERSION,
        'actions' => {}
      }
      gem_manager = Actions::GemManager.new( @logger )
      action_versions = gem_manager.activate_installed_gems
      versions[ 'actions' ] = action_versions
  
      defined_actions = Actions.defined_actions

      if defined_actions.any?
        @logger.debug "Available actions are: #{defined_actions}"
      else
        @logger.ops_warn 'No defined actions.  Please make sure Standard and/or Custom Actions are installed.'
      end

      versions
    end

    def run
      # Stop agents before stopping armagh
      TERM_SIGNALS.each do |signal|
        trap(signal) { shutdown(signal) }
      end

      begin
        @logger.any 'Setting up MongoDB indexes.  This may take a while...'
        Connection.setup_indexes

        @logger.any 'Armagh started'

        @agent_status = AgentStatus.new
        @server = DRb.start_service(IPC::DRB_URI, @agent_status)

        apply_config

        @collection_trigger.start

        @running = true
        checkin('running')

        while @running do
          if @last_checkin.nil? || @last_checkin < Time.now - @config.launcher.checkin_frequency
            reconcile_agents
            refresh_config
            checkin('running')
          end

          recover_dead_agents
          sleep 1
        end

      rescue => e
        Logging.dev_error_exception(@logger, e, 'An unexpected error occurred.  Exiting.')
        shutdown(:SIGINT)
        @exit_status = 1
      end

      checkin('stopping')

      Process.waitall
      @server.stop_service
      DRb.thread.join

      checkin('stopped')

      @logger.any 'Armagh stopped'

      exit @exit_status if @exit_status
    end
  end
end
