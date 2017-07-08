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

require_relative '../connection'
require_relative '../utils/db_doc_helper'

module Armagh
  module Status
    class AgentStatus < Connection::DBDoc
      def self.default_collection
        Connection.agent_status
      end

      def self.report(id:, hostname:, status:, task:, running_since:, idle_since:)
        agent_status = new
        agent_status.internal_id = id
        agent_status.hostname = hostname
        agent_status.status = status
        agent_status.task = task
        agent_status.running_since = running_since
        agent_status.idle_since = idle_since
        agent_status.last_updated = Time.now
        agent_status.save
        agent_status
      end

      def self.delete(id)
        db_delete({'_id' => id})
      rescue => e
        raise Connection.convert_mongo_exception(e, id: id, type_class: self.class)
      end

      def self.find(id, raw: false)
        db_status = self.db_find_one('_id' => id)
        raw ? db_status : new(db_status)
      rescue => e
        raise Connection.convert_mongo_exception(e, id: id, type_class: self.class)
      end

      def self.find_all(raw: false)
        db_statuses = self.db_find({}).to_a.compact

        if raw
          statuses = db_statuses
        else
          statuses = []
          db_statuses.each do |status|
            statuses << new(status)
          end
        end

        statuses
      rescue => e
        raise Connection.convert_mongo_exception(e, type_class: self.class)
      end

      def self.find_all_by_hostname(hostname, raw: false)
        db_agent_statuses = self.db_find({'hostname' => hostname}).to_a.compact

        if raw
          agent_statuses = db_agent_statuses
        else
          agent_statuses = []
          db_agent_statuses.each do |agent_status|
            agent_statuses << new(agent_status)
          end
        end

        agent_statuses
      rescue => e
        raise Connection.convert_mongo_exception(e, id: hostname, type_class: self.class)
      end

      def save
        Utils::DBDocHelper.clean_model(self)
        self.class.db_replace({'_id' => internal_id}, @db_doc)
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def hostname=(hostname)
        @db_doc['hostname'] = hostname
      end

      def hostname
        @db_doc['hostname']
      end

      def status=(status)
        @db_doc['status'] = status
      end

      def status
        @db_doc['status']
      end

      def task=(task)
        @db_doc['task'] = task
      end

      def task
        @db_doc['task']
      end

      def running_since=(running_since)
        @db_doc['running_since'] = running_since
      end

      def running_since
        @db_doc['running_since']
      end

      def idle_since=(idle_since)
        @db_doc['idle_since'] = idle_since
      end

      def idle_since
        @db_doc['idle_since']
      end

      def last_updated=(last_updated)
        @db_doc['last_updated'] = last_updated
      end

      def last_updated
        @db_doc['last_updated']
      end
    end
  end
end
