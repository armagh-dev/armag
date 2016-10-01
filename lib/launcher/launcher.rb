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

require 'rubygems'
require 'bundler/setup'

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
require_relative '../utils/collection_trigger'
require_relative '../connection'
require_relative '../ipc'
require_relative '../logging'
require_relative '../version'

module Armagh
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
        errors << "Log level must be one of #{ Logging.valid_levels.join(', ')}"
      end
      errors
    end
    
    def initialize( launcher_name = 'default' )

      @logger = Logging.set_logger('Armagh::Application')  

      unless Connection.can_connect?
        @logger.error "Unable to establish connection to the MongoConnection database configured in '#{Configuration::FileBasedConfiguration.filepath}'.  Ensure the database is running."
        exit 1
      end
      
      @versions = get_versions
      Document.version['armagh'] = @versions[ 'armagh' ]
      @versions[ 'actions' ].each do |package, version|
        Document.version[ package ] = version
      end

      bind_ip = ENV[ "ARMAGH_BIND_IP" ] || '127.0.0.1'
      launcher_config_name = [ bind_ip, launcher_name ].join("_")
      @config = Launcher.find_or_create_configuration( Connection.config, launcher_config_name, values_for_create: {} )
      
      @agent_config = Agent.find_or_create_configuration( Connection.config, 'default', values_for_create: {} )
      @workflow = Actions::Workflow.new( @logger, Connection.config )
      @collection_trigger = Utils::CollectionTrigger.new(@workflow)
      
      @hostname = Socket.gethostname
      @agents = {}
      @running = false
    end

    def reconcile_agents
      reported_agents = AgentStatus.get_statuses(@agent_status).keys
      running_agents = @agents.values.collect{|a| a.uuid}

      reported_not_running = reported_agents - running_agents
      running_not_reported = running_agents - reported_agents

      reported_not_running.each {|id| @agent_status.remove_agent(id) }

      @logger.error "The following agents are reported but not running: #{reported_not_running.join(", ")}" unless reported_not_running.empty?
      @logger.error "The following agents are running but not reporting: #{running_not_reported}.join(", ")" unless running_not_reported.empty?
    end

    def checkin(status)
      @logger.info "Checking In: #{status}"

      checkin = {
          'versions' => @versions,
          'last_update' => Time.now,
          'status' => status,
          'agents' => AgentStatus.get_statuses(@agent_status)
      }

      @logger.debug "Checkin Details: #{checkin}"
      Connection.status.find('_id' => @hostname).replace_one(checkin, {upsert: true})

      @last_checkin = Time.now
    rescue => e
      raise Connection.convert_exception(e)
    end

    def apply_config
      Logging.set_level(@logger, @config.launcher.log_level)
      change_num_agents(@config.launcher.num_agents)
      @logger.debug "Updated configuration to log level #{ @config.launcher.log_level }, num agents #{ @config.launcher.num_agents }"
    end

    def change_num_agents(num_agents)
      running_agents = @agents.length
      @logger.debug "Changing number of agents from #{running_agents} to #{num_agents}"

      if running_agents < num_agents
        @logger.info "Increasing number of agents from #{running_agents} to #{num_agents}"
        launch_agents(num_agents - running_agents)
      elsif running_agents > num_agents
        @logger.info "Decreasing number of agents from #{running_agents} to #{num_agents}"
        kill_agents(running_agents - num_agents)
      end
    end

    def launch_agents(num_agents)
      @logger.debug "Launching #{num_agents} agents"
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
        TERM_SIGNALS.each do |signal|
          trap(signal) {agent.stop}
        end
        begin
          agent.start
        rescue => e
          Logging.dev_error_exception(@logger, e, "Could not start agent #{agent.uuid}")
        end
      end

      @agents[pid] = agent
    end

    def stop_agent(signal)
      pid = @agents.keys.first
      Process.kill(signal, pid)
      pid = Process.wait
      pid
    end

    def shutdown(signal)
      Thread.new{ @logger.any "Received #{signal}.  Shutting down once agents finish" }
      @running = false
      Thread.new{ kill_all_agents(signal) }
      @collection_trigger.stop
    end

    def refresh_config
      if @config.refresh || @agent_config.refresh || @workflow.refresh
        @logger.info "Configuration change detected.  Restarting agents..."
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

      begin
        require 'armagh/standard_actions'
        @logger.info "Using StandardActions: #{StandardActions::VERSION}"
        versions[ 'actions' ][ 'standard' ] = StandardActions::VERSION
      rescue LoadError
        @logger.ops_warn "StandardActions gem is not deployed. These actions won't be available."
      rescue => e
        # An unexpected exception - things like syntax errors.
        Logging.dev_error_exception(@logger, e, 'Could not load StandardActions gem')
        Armagh.send(:remove_const, :StandardActions)
      end

      begin
        require 'armagh/custom_actions'
        @logger.info "Using CustomActions: #{Armagh::CustomActions::NAME} (#{CustomActions::VERSION})"
        versions[ 'actions' ][CustomActions::NAME] = CustomActions::VERSION
      rescue LoadError
        @logger.ops_warn "CustomActions gem is not deployed. These actions won't be available."
      rescue => e
        # An unexpected exception - things like syntax errors.
        Logging.dev_error_exception(@logger, e, 'Could not load CustomActions gem')
        Armagh.send(:remove_const, :CustomActions)
      end

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
        kill_all_agents(:SIGINT)
        @collection_trigger.stop
        @exit_status = 1
      end

      checkin('stopping')

      @collection_trigger.stop
      Process.waitall
      @server.stop_service


      checkin('stopped')

      @logger.any 'Armagh stopped'

      exit @exit_status if @exit_status
    end
  end
end
