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

require 'tsort'

require 'armagh/actions'
require 'armagh/documents'

require_relative '../connection'
require_relative '../utils/t_sortable_hash'

module Armagh
  module Actions
    
    class ConfigurationError < StandardError; end
    
    class Workflow
      
      def initialize( logger, config_store )
        
        @logger = logger
        @last_timestamp = Time.at(0)
        @input_docspecs = {}
        @output_docspecs = {}
        @config_store = config_store
        @action_configs = {}
        refresh 
        
      end
      
      def set_logger( logger )
        @logger = logger 
      end
      
      def refresh
        
        configs_in_db = Action.find_all_configurations( @config_store, include_descendants: true )
        ts_in_db      = configs_in_db.max_by{ |configured_class, config| config.__timestamp }
        return false if ts_in_db == @last_timestamp
        
        warnings, new_input_docspecs, new_output_docspecs = validate_and_return_warnings_inputs_outputs( configs_in_db )
        ops_warn "While refreshing action workflow: #{warnings}" if warnings
        
        @input_docspecs = new_input_docspecs
        @output_docspecs = new_output_docspecs
        @action_configs.clear
        @action_configs = Hash[ configs_in_db.collect{ |configured_class, config| [ config.__name, config ] } ]
        
        @last_timestamp = ts_in_db
        
        return true
        
      end
      
      def validate_and_return_warnings_inputs_outputs( configs )
        
        warnings = []
        
        try_input_docspecs  = {}
        try_output_docspecs = {}
        try_docspec_flows   = Utils::TsortableHash.new
        
        begin
          configs.each do | action_class_name, config |
            if config.action.active
              try_input_docspecs[ config.input.docspec ] ||= []
              try_input_docspecs[ config.input.docspec ] << config
              config.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' }.each do |docspec_param|
                docspec = docspec_param.value
                try_output_docspecs[ docspec ] ||= []
                try_output_docspecs[ docspec ] << config
                try_docspec_flows[ config.input.docspec ] ||= []
                try_docspec_flows[ config.input.docspec ] << docspec
              end
            end
          end
        rescue Configh::UnrecognizedTypeError => e
          raise Actions::ConfigurationError, e.message
        end
        
        unused_docspecs = try_output_docspecs.keys - try_input_docspecs.keys
        warnings << "Following docspecs created but not used: #{ unused_docspecs.collect{ |d| d.type }.join(', ')}" unless unused_docspecs.empty?
        
        uncreated_docspecs = try_input_docspecs.keys - try_output_docspecs.keys
        uncreated_docspecs.delete_if{ |ds| ds.type[/^__COLLECT__/] }
        warnings << "Following docspecs sought but not created: #{ uncreated_docspecs.collect{ |d| d.type }.join(', ')}" unless uncreated_docspecs.empty?
        
        begin
          try_docspec_flows.tsort
        rescue TSort::Cyclic
          raise ConfigurationError, 'Action configuration has a cycle.'
        end
        
        [ warnings.empty? ? nil : warnings.join(', '), try_input_docspecs, try_output_docspecs ]
      end
      
      def get_action( action_name, caller, logger )
        
        c = @action_configs[ action_name ]
        return nil unless c
        
        c.__type.new( caller, logger, c )
      end
        
      def get_action_names_for_docspec( docspec )
        
        @input_docspecs
          .collect{ |in_docspec,configs| configs.collect{ |config| config.__name if docspec == in_docspec }}
          .flatten
          .compact
      end
      
    end
  end
end