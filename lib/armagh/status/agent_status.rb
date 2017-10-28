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
require_relative '../document/base_document/document'
require_relative '../document/base_document/delegated_attributes'

module Armagh
  module Status
    class AgentStatus < BaseDocument::Document

      delegated_attr_accessor :signature
      delegated_attr_accessor :hostname
      delegated_attr_accessor :status
      delegated_attr_accessor :task
      delegated_attr_accessor :running_since
      delegated_attr_accessor :idle_since

      def self.default_collection
        Connection.agent_status
      end

      def self.report(signature:, hostname:, status:, task:, running_since:, idle_since:)
        upsert_one( { 'signature' => signature },
                    { 'signature' => signature,
                      'hostname' => hostname,
                      'status' => status,
                      'task' => task,
                      'running_since' => running_since,
                      'idle_since' => idle_since
                    }
        )
      end

       def self.find_all( raw: false )
        docs = find_many( {} )
        docs.collect!{ |d| d.to_hash } if raw
        docs
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{self.class}")
      end

      def self.find_all_by_hostname(hostname, raw: false )
        docs = find_many( { 'hostname' => hostname })
        docs.collect!{ |d| d.to_hash } if raw
        docs
      rescue => e
        raise Connection.convert_mongo_exception(e, natural_key: "#{self.class} #{hostname}" )
      end

      def self.delete( signature )
        super( { 'signature' => signature })
      end

    end
  end
end
