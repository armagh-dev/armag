#!/usr/bin/env ruby
#
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

require 'etc'
require 'fileutils'
require 'socket'

require 'configh'

require_relative '../environment'
Armagh::Environment.init

require_relative '../authentication'
require_relative '../agent/agent'
require_relative '../actions/workflow_set'
require_relative '../actions/gem_manager'
require_relative '../connection'
require_relative '../document/document'
require_relative '../status'
require_relative '../logging'
require_relative '../utils/scheduled_action_trigger'
require_relative '../version'

module Armagh

  class InitializationError < StandardError; end

  class Launcher
    CONFIG_NAME = 'default'

    include Configh::Configurable

    define_parameter name: "num_agents",        description: "Number of agents",                      type: 'positive_integer', required: true, default: 1,      group: 'launcher'
    define_parameter name: "update_frequency",  description:  "Configuration refresh rate (seconds)", type: 'positive_integer', required: true, default: 60,     group: 'launcher'
    define_parameter name: "checkin_frequency", description: "Status update rate (seconds)",          type: 'positive_integer', required: true, default: 60,     group: 'launcher'
    define_parameter name: "log_level",         description: "Log level",                             type: 'string',           required: true, options:  Armagh::Logging.valid_log_levels.collect{|s| s.encode('UTF-8')}, default: 'info', group: 'launcher'

    TERM_SIGNALS = [:INT, :QUIT, :TERM]

    def Launcher.config_name( launcher_name = CONFIG_NAME )
      [ Connection.ip, launcher_name ].join("_")
    end

    def Launcher.get_versions(logger, action_versions)
      versions = {
        'armagh'  => VERSION,
        'actions' => {}
      }

      versions[ 'actions' ] = action_versions
      defined_actions = Actions.defined_actions

      if defined_actions.any?
        logger.debug "Available action classes are: #{defined_actions}"
      else
        logger.ops_warn 'No defined actions.  Please make sure Standard and/or Custom Actions are installed.'
      end

      versions
    end

    def initialize( launcher_name = CONFIG_NAME )
      @logger = Logging.set_logger('Armagh::Application::Launcher')

      Connection.require_connection(@logger)
      
      bind_ip = Connection.ip
      launcher_config_name = [ bind_ip, launcher_name ].join('_')

      @config = Launcher.find_or_create_configuration( Connection.config, launcher_config_name, values_for_create: {}, maintain_history: true )
      @logger.any "Using Launcher Config: #{launcher_config_name}"

      Logging.set_level(@logger, @config.launcher.log_level)

      action_versions = Actions::GemManager.instance.activate_installed_gems(@logger)

      @versions = self.class.get_versions(@logger, action_versions)
      Document.version['armagh'] = @versions[ 'armagh' ]
      @versions[ 'actions' ].each do |package, version|
        Document.version[ package ] = version
      end

      Armagh::Authentication.setup_authentication

      @agent_config = Agent.find_or_create_configuration( Connection.config, Agent::CONFIG_NAME, values_for_create: {}, maintain_history: true )

      begin
        @workflow_set = Actions::WorkflowSet.for_agent( Connection.config )
        @logger.any 'workflow init successful'
      rescue Actions::WorkflowInitError, Actions::WorkflowActivationError
        raise InitializationError, 'Workflow initialization failed, because at least one configuration in the database has an error. Review current workflow settings in the admin GUI to fix the problem.'
      end

      @authentication_config = Authentication.config

      @archive_config = Utils::Archiver.find_or_create_config(Connection.config)

      @scheduled_action_trigger = Utils::ScheduledActionTrigger.new(@workflow_set)
      Logging.set_level(@scheduled_action_trigger.logger,  @config.launcher.log_level)


      @hostname = Socket.gethostname
      @agents = {}
      @running = false
      @shutdown = false
    rescue => e
      Logging.dev_error_exception(@logger, e, 'Error initializing launcher')
      exit 1
    end

    def reconcile_agents
      reported_agents = Status::AgentStatus.find_all_by_hostname(@hostname).collect{|a| a.signature}
      running_agents = @agents.values.collect{|a| a.signature}

      reported_not_running = reported_agents - running_agents
      running_not_reported = running_agents - reported_agents

      reported_not_running.each {|id| remove_agent_status(id) }

      @logger.error "The following agents are reported but not running: #{reported_not_running.join(', ')}" unless reported_not_running.empty?
      @logger.error "The following agents are running but not reporting: #{running_not_reported.join(', ')}" unless running_not_reported.empty?
    end

    def checkin(status)
      @logger.debug "Checking In: #{status}"
      started = status == Status::RUNNING ? @started : nil
      Status::LauncherStatus.report(hostname: @hostname, status: status, versions: @versions, started: started)
      @last_checkin = Time.now
    rescue => e
      raise Connection.convert_mongo_exception(e)
    end

    def apply_config
      Logging.set_level(@logger, @config.launcher.log_level)
      Logging.set_level(@scheduled_action_trigger.logger, @config.launcher.log_level)
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

    def kill_all_agents(signal = :INT)
      kill_agents(@agents.length, signal)
    end

    def kill_agents(num_agents, signal = :INT)
      return if num_agents == 0

      Thread.new{ @logger.any "Killing #{num_agents} agent(s)." }.join
      num_agents.times do
        pid = @agents.keys.first
        next unless pid
        agent_id = @agents[pid].signature

        Thread.new{ @logger.any "Killing #{agent_id}." }.join
        Process.kill(signal, pid)
        begin
          pid = Process.wait
        rescue Errno::ECHILD; end

        @agents.delete pid
        remove_agent_status(agent_id)
      end
    end

    def remove_agent_status(agent_id)
      Status::AgentStatus.delete(agent_id)
    end

    def recover_dead_agents
      num_dead_agents = 0
      @agents.each do |pid, agent|
        wait_pid, status = Process.waitpid2(pid, Process::WNOHANG)
        if wait_pid
          @logger.error "Agent #{agent.signature} (PID: #{pid}) terminated with exit code #{status}. Restarting it"
          num_dead_agents += 1
          agent_id = @agents[pid].signature
          @agents.delete(pid)
          remove_agent_status(agent_id)
          Connection.all_document_collections.each do |coll|
            Document.force_unlock_all_in_collection_held_by(agent_id, collection:coll)
          end
        end
      end

      launch_agents(num_dead_agents)
    end

    def start_agent_in_process
      agent = Agent.new( @agent_config, @archive_config, @workflow_set, @hostname )

      pid = Process.fork do
        Process.setproctitle("#{agent.signature}")
        TERM_SIGNALS.each do |signal|
          trap(signal) {agent.stop}
        end
        begin
          agent.start unless @shutdown
          @logger.info "Agent #{agent.signature} terminated"
        rescue => e
          Logging.dev_error_exception(@logger, e, "Could not start agent #{agent.signature}")
        end
      end

      @agents[pid] = agent
    end

    def shutdown(signal)
      Thread.new{ @logger.any "Received #{signal}.  Shutting down once agents finish" }.join
      @running = false
      @shutdown = true
      @scheduled_action_trigger.stop
      Thread.new{kill_all_agents(signal)}.join
    end

    def refresh_config
      @logger.debug 'Checking for updated configuration'

      # Explicitly call them all out to refresh all if there any any to refresh
      config = @config.refresh
      agent_config = @agent_config.refresh
      workflow_set = @workflow_set.refresh
      authentication_config = @authentication_config.refresh
      archive_config = @archive_config.refresh

      if config || agent_config || workflow_set || archive_config || authentication_config
        @logger.any 'Configuration change detected.  Restarting agents...'

        @logger.debug {
          changed_configs = []
          changed_configs << 'launcher' if config
          changed_configs << 'agent' if agent_config
          changed_configs << 'workflow_set' if workflow_set
          changed_configs << 'archive_config' if archive_config
          changed_configs << 'authentication_config' if authentication_config
          "Triggered by configuration changes to #{changed_configs.join(', ')}"
        }

        kill_all_agents
        apply_config
      else
        @logger.debug 'No configuration updates to apply.'
      end
    rescue => e
      Logging.ops_error_exception(@logger, e, 'A configuration error was detected.  Ignoring the configuration and stopping all agents.')
      kill_all_agents
    end

    def run
      return if @running

      @started = Time.now.utc

      # Stop agents before stopping armagh
      TERM_SIGNALS.each do |signal|
        trap(signal) { shutdown(signal) }
      end

      begin
        @logger.any 'Setting up MongoDB indexes.  This may take a while...'
        Connection.setup_indexes
        @logger.any 'Armagh started'

        apply_config

        if !@shutdown
          @scheduled_action_trigger.start
          @running = true
          checkin(Status::RUNNING)
        end

        while @running && !@shutdown do
          if @last_checkin.nil? || @last_checkin < Time.now - @config.launcher.checkin_frequency
            reconcile_agents
            refresh_config
            checkin(Status::RUNNING)
          end

          recover_dead_agents
          sleep 1
        end

      rescue => e
        Logging.dev_error_exception(@logger, e, 'An unexpected error occurred.  Exiting.')
        shutdown(:INT)
        @exit_status = 1
      end

      checkin(Status::STOPPING)
      Process.waitall
      checkin(Status::STOPPED)

      @logger.any 'Armagh stopped'
      exit @exit_status if @exit_status
    end
  end
end
