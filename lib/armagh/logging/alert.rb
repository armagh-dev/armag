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

module Armagh
  module Logging

    class AlertClearingError < StandardError; end

    class Alert

      def self.get_counts( workflow:nil, action:nil )
        filter = { 'alert' => true }
        filter[ 'workflow' ] = workflow if workflow
        filter[ 'action' ] = action if action
        counts_by_warn_error_fatal = { 'warn' => 0, 'error' => 0, 'fatal' => 0}

        Connection.log.aggregate(
            [
                { '$match' => filter },
                { '$group' => {
                    '_id' => '$level',
                    'count' => { '$sum' => 1 }
                   }
                }
            ]
        ).each do |count|
          wef_level = count[ '_id' ].downcase[ /(warn|error|fatal)/]
          counts_by_warn_error_fatal[ wef_level ] += count[ 'count' ] if wef_level
        end

        counts_by_warn_error_fatal
      end

      def self.get( workflow:nil, action:nil )
        filter = { 'alert' => true }
        filter[ 'workflow' ] = workflow if workflow
        filter[ 'action' ] = action if action

        Connection.log.find( filter ).collect{ |alerted_log_entry|
          { '_id'          => alerted_log_entry[ '_id' ],
            'level'        => alerted_log_entry[ 'level' ],
            'timestamp'    => alerted_log_entry[ 'timestamp' ],
            'workflow'     => alerted_log_entry[ 'workflow' ],
            'action'       => alerted_log_entry[ 'action' ],
            'full_message' => [alerted_log_entry['message'], alerted_log_entry['exception']&.[]('message')].compact.join(': ')
          }
        }
      end

      def self.clear( internal_id: nil, workflow: nil, action: nil )
        raise AlertClearingError, "must provide one of internal_id, workflow, or action" unless [ internal_id, workflow, action ].compact.length == 1
        filter = { 'alert' => true }
        filter[ '_id' ] = internal_id if internal_id
        filter[ 'workflow' ] = workflow if workflow
        filter[ 'action' ] = action if action

        Connection.log.update_one( filter, { '$unset' => { 'alert' => 1 }})
      end
    end
  end
end
