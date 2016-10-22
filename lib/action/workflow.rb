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
      attr_accessor :config_store

      def initialize( logger, config_store )
        
        @logger = logger
        @last_timestamp = Time.at(0)
        @input_docspecs = {}
        @output_docspecs = {}
        @config_store = config_store
        @action_configs_by_name = {}
        refresh    
      end
      
      def set_logger( logger )
        @logger = logger 
      end
      
      def refresh(force = false)
        configs_with_classes_in_db = Action.find_all_configurations( @config_store, include_descendants: true )
        configs_in_db = configs_with_classes_in_db.collect{ | _klass, config| config }
        ts_in_db = configs_in_db.collect{ |c| c.__timestamp }.max

        return false if ts_in_db == @last_timestamp && !force
        
        warnings, 
        new_input_docspecs, 
        new_output_docspecs = Workflow.validate_and_return_warnings_inputs_outputs( configs_in_db )
        
        @action_names_by_input_docspecs = new_input_docspecs
        @action_names_by_output_docspecs = new_output_docspecs
        @action_configs_by_name = Hash[ configs_in_db.collect{ | config | [ config.action.name, config ]}]
        @last_timestamp = ts_in_db
        
        return true   
      end
      
      def Workflow.validate_and_return_warnings_inputs_outputs( configs )
        
        warnings = []
        
        try_input_docspecs  = {}
        try_output_docspecs = {}
        try_docspec_flows   = Utils::TsortableHash.new
        
        begin
          configs.each do |config|
            if config.action.active
              try_input_docspecs[ config.input.docspec ] ||= []
              try_input_docspecs[ config.input.docspec ] << config.action.name
              config.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' }.each do |docspec_param|
                docspec = docspec_param.value
                try_output_docspecs[ docspec ] ||= []
                try_output_docspecs[ docspec ] << config.action.name
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
        
        #TODO verify only one divider per doctype
        
        [ warnings.empty? ? nil : warnings.join(', '), try_input_docspecs, try_output_docspecs ]
      end
      
      def instantiate_action( action_name, caller, logger, state_collection )
        
        c = @action_configs_by_name[ action_name ]
        return nil unless c
        
        c.__type.new( caller, logger.fullname + "::#{action_name}", c, state_collection )
      end
        
      def get_action_names_for_docspec( docspec )
        action_names = []
        @action_names_by_input_docspecs.each do |input_docspec, action_names_array|
          action_names.concat action_names_array if input_docspec == docspec
        end
        action_names
      end

      def instantiate_divider( docspec, caller, logger, state_collection )

        divider_action_name = get_action_names_for_docspec( docspec )
                                .find{ |action_name| @action_configs_by_name[ action_name ].__type < Divide }
        instantiate_action( divider_action_name, caller, logger, state_collection ) if divider_action_name
      end
    
      def create_action( action_class_name, candidate_configuration_values )

        candidate_action_name = candidate_configuration_values&.dig( 'action', 'name' )
        raise( ConfigurationError, "Action named #{ candidate_action_name } already exists.") if @action_configs_by_name[ candidate_action_name ]
        
        update_action( action_class_name, candidate_configuration_values )
      end
      
      def update_action( action_class_name, candidate_configuration_values )
          
        candidate_action_name = candidate_configuration_values&.dig( 'action', 'name' )
        raise ConfigurationError, "Configuration must include an action name" unless candidate_action_name
        raise ConfigurationError, "Action class name must be provided" unless action_class_name.is_a?(String)
        raise ConfigurationError, "Action class must be member of Armagh::StandardActions or Armagh::CustomActions" unless action_class_name[/^Armagh::(Standard|Custom)Actions::/]
        begin
          action_class = eval( action_class_name )
        rescue
          raise ConfigurationError, "Action class #{ action_class_name } is not defined"
        end

        candidate_config = nil
        begin
          candidate_config = action_class.create_configuration( @config_store, candidate_action_name, candidate_configuration_values )
        rescue Configh::ConfigInitError => e
          raise ConfigurationError, e.message
        end
        candidate_action_configs = @action_configs_by_name.values
        candidate_action_configs.delete_if{ |ac| ac.action.name == candidate_action_name }
        candidate_action_configs << candidate_config
        
        begin
          warnings, new_input_docspecs, new_output_docspecs = Workflow.validate_and_return_warnings_inputs_outputs( candidate_action_configs )
        rescue => e
          raise( ConfigurationError, e.message )
        end
        
        action_class.create_configuration( @config_store, candidate_action_name, candidate_configuration_values ) 
        refresh(true)
      end
      
      def activate_actions( actions )
        
        actions.each do |action_class_name, action_name|
          @logger.debug "activating #{ action_class_name }: #{action_name}"
          config = eval( action_class_name ).find_configuration( @config_store, action_name ).__values
          config[ 'action' ][ 'active' ] = true
          update_action( action_class_name, config )
        end
      end
    end
  end
end