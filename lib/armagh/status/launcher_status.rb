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

require_relative '../connection'
require_relative '../document/base_document/document'

module Armagh
  module Status
    class LauncherStatus < BaseDocument::Document

      delegated_attr_accessor :hostname
      delegated_attr_accessor :versions
      delegated_attr_accessor :status
      delegated_attr_accessor :started, validates_with: :utcize_ts

      def self.default_collection
        Connection.launcher_status
      end

      def self.report(hostname:, status:, versions:, started:)
        upsert_one(
            { 'hostname' => hostname },
            { 'hostname' => hostname,
              'status' => status,
              'versions' => versions,
              'started' => started }
        )
      end

      def self.find_all(raw: false)
        docs = find_many({})
        docs.collect!{ |d| d.to_hash } if raw
        docs
      end

    end
  end
end
