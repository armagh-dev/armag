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
    class LauncherStatus < Connection::DBDoc
      def self.default_collection
        Connection.launcher_status
      end

      def self.report(hostname:, status:, versions:)
        launcher_status = new
        launcher_status.hostname = hostname
        launcher_status.status = status
        launcher_status.versions = versions
        launcher_status.last_updated = Time.now
        launcher_status.save
        launcher_status
      end

      def self.delete(hostname)
        self.db_delete({'_id' => hostname})
      rescue => e
        raise Connection.convert_mongo_exception(e, id: hostname, type_class: self.class)
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

      def save
        Utils::DBDocHelper.clean_model(self)
        self.class.db_find_and_update({'_id' => internal_id}, @db_doc)
      rescue => e
        raise Connection.convert_mongo_exception(e, id: internal_id, type_class: self.class)
      end

      def hostname=(hostname)
        self.internal_id = hostname
      end

      def hostname
        self.internal_id
      end

      def status=(status)
        @db_doc['status'] = status
      end

      def status
        @db_doc['status']
      end

      def versions=(versions)
        @db_doc['versions'] = versions
      end

      def versions
        @db_doc['versions']
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
