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

require_relative '../logging/global_logger'

module Armagh
  class AgentStatus

    attr_reader :config, :statuses

    def initialize
      @config = {}
      @statuses = {}
      @lock = Mutex.new
    end

    # Preferred way to access statuses so we don't risk operating on the shared object.  Can't use dup in the instance because
    # the dup object will immediately be GC'd by the server.
    def self.get_statuses(agent_status)
      agent_status.statuses.dup
    end

    # Preferred way to access config so we don't risk operating on the shared object.  Can't use dup in the instance because
    # the dup object will immediately be GC'd by the server.
    def self.get_config(agent_status, last_config_received = nil)
      if last_config_received.nil? || last_config_received < agent_status.config['timestamp']
        agent_status.config.dup
      else
        nil
      end
    end

    def report_status(agent_id, status)
      @lock.synchronize do
        @statuses[agent_id] = status
      end
    end

    def remove_agent(agent_id)
      @lock.synchronize do
        @statuses.delete(agent_id)
      end
    end

    def config=(config)
      @lock.synchronize do
        @config = config
      end
    end

    def update_config(key, value)
      @lock.synchronize do
        @config[key] = value
      end
    end
  end
end
