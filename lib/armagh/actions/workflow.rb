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
#
require 'tsort'
require 'configh'

require_relative '../utils/t_sortable_hash'
require_relative '../logging/alert'
require_relative '../status'

module Armagh
  module Actions

    class WorkflowInitError < StandardError; end
    class WorkflowConfigError < StandardError; end
    class WorkflowActivationError < StandardError; end
    class WorkflowDocumentsInProcessError < StandardError; end

    class ActionConfigError < StandardError
      attr_reader :config_markup
      def initialize( message, config_markup=nil )
        @config_markup=config_markup
        super(message)
      end
    end
    class ActionFindError < StandardError; end

    class Workflow
      include Configh::Configurable
      attr_reader :name, :valid_action_configs, :invalid_action_configs, :invalid_bypassed_configs, :retired_action_configs, :actions, :has_no_cycles

      VALID_RUN_MODES = [ Armagh::Status::RUNNING, Armagh::Status::STOPPING, Armagh::Status::STOPPED ]

      define_parameter name: 'run_mode', type: 'string', description: VALID_RUN_MODES.join(", "), required: true, default: Armagh::Status::STOPPED, group: 'workflow'
      define_parameter name: 'retired',  type: 'boolean', description: 'not normally displayed', required: true, default: false, group: 'workflow'
      define_parameter name: 'unused_output_docspec_check', type: 'boolean', description: 'verify that there are no unused output docspecs', required: true, default: true, group: 'workflow'
      define_group_validation_callback callback_class: Workflow, callback_method: 'check_run_mode'

      def self.check_run_mode(candidate_config)
        error = nil
        unless VALID_RUN_MODES.include? candidate_config.workflow.run_mode
          error = "run_mode must be one of: #{VALID_RUN_MODES.join(", ")}"
        end
        error
      end

      def self.create( config_store, name, workflow_set, logger: nil )
        workflow_config = create_configuration(config_store, name, {}, maintain_history:true )
        new(config_store, name, workflow_config, workflow_set, logger: logger )
      rescue WorkflowInitError, Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      def self.edit_configuration( config_values, creating_in: )
        edit = super( config_values )
        name = config_values.dig('workflow','name')
        if creating_in && name && exists?( creating_in, name)
          raise WorkflowConfigError, 'Workflow name already in use'
        end
        edit
      end

      def self.find( config_store, name, workflow_set, logger: nil )
        raise WorkflowConfigError, 'create requires a workflow name' if name.nil? || name.empty?
        workflow_config = find_configuration( config_store, name )
        if workflow_config
          new(config_store, name, workflow_config, workflow_set, logger: logger )
        end
      rescue Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      def self.exists?( config_store, name )
        raise WorkflowConfigError, 'exists? requires a workflow name' if name.nil? || name.empty?
        begin
          !find_configuration( config_store, name ).nil?
        rescue Configh::ConfigInitError => e
          raise WorkflowConfigError, e.message
        end
      end

      def self.find_all( config_store, workflow_set, logger: nil )
        workflows = []

        workflow_configs = find_all_configurations( config_store )
        workflow_configs.each do |_klass,workflow_config|
          name = workflow_config.__name
          workflows << new(config_store, name, workflow_config, workflow_set, logger: logger )
        end
        workflows
      rescue Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      private_class_method :new

      def initialize(config_store, name, config_object, workflow_set, logger: nil )

        raise WorkflowInitError, 'name cannot be nil' if name.nil? || name.empty?

        @config_store = config_store
        @name = name
        @config = config_object
        @workflow_set = workflow_set
        @valid_action_configs = []
        @invalid_action_configs = []
        @retired_action_configs = []
        @has_no_cycles = true
        @check_unused_outputs = unused_output_docspec_check
        @unused_outputs = {}
        @logger = logger

        load_action_configs
      end

      def create_action_config( type, cand_config_values, bypass_validation: false )
        update_action_config( type, cand_config_values, creating: true, bypass_validation: bypass_validation )
      end

      def update_action_config( type, cand_config_values, creating: false, bypass_validation: false )

        raise( WorkflowConfigError, 'Stop workflow before making changes' ) unless stopped?

        begin
          action_class = Actions.name_to_class( type )
        rescue => e
          raise ActionFindError, e.message
        end

        cand_action_name = cand_config_values&.dig( 'action', 'name' )
        cand_config_values.dig('action')&.[]=('workflow', @name)
        cand_config_values.dig('action')&.[]=('active', false )

        config = nil
        begin
          if creating
            config = action_class.create_configuration(@config_store, cand_action_name, cand_config_values, maintain_history: true, bypass_validation: bypass_validation )
          else
            config = action_class.force_update_configuration(@config_store, cand_action_name, cand_config_values, maintain_history: true, bypass_validation: bypass_validation )
          end
          load_action_configs
          @workflow_set.refresh_pointers
          config
        rescue Configh::ConfigInitError => e
          config_with_errors = action_class.edit_configuration(cand_config_values)
          if e.message == 'Name already in use'
            action_name_config = config_with_errors['parameters'].find{ |p_config| p_config['group'] == 'action' and p_config['name'] == 'name' }
            action_name_config['error'] = 'already in use' if action_name_config
          end
          raise ActionConfigError.new("Configuration has errors: #{e.message}", config_with_errors)
        rescue Configh::ConfigValidationError, InvalidArgumentError => e
          config_with_errors = action_class.edit_configuration(cand_config_values)
          raise ActionConfigError.new("Configuration has errors: #{e.message}", config_with_errors)
        end
      end

      def load_action_configs
        @valid_action_configs     = []
        @invalid_action_configs   = []
        @invalid_bypassed_configs = []
        @retired_action_configs   = []

        Action.find_all_configurations(@config_store, include_descendants:true, raw:true)
          .each do |klass, raw_action_config|
          is_retired = raw_action_config.dig('values', 'action', 'retired') == 'true'
          if raw_action_config['values'].dig('action','workflow') == @name
            if klass.configuration_values_valid?(raw_action_config['values'])
              action = klass.find_configuration(@config_store, raw_action_config['name'])
              if is_retired
                @retired_action_configs << action
              else
                @valid_action_configs << action
              end
            else
              action = klass.find_configuration(@config_store, raw_action_config['name'], bypass_validation: true)
              if is_retired
                @retired_action_configs << action
              else
                @invalid_bypassed_configs << action
                @invalid_action_configs << klass.edit_configuration(raw_action_config['values'])
              end
            end
          end
        end
        if actions_valid?
          @has_no_cycles = Workflow.actions_have_no_cycles?(@valid_action_configs)
        end
        @check_unused_outputs = @config.workflow.unused_output_docspec_check
      end

      def retired
        @config.workflow.retired
      end

      def retired=(retire)
        raise(WorkflowConfigError, 'Stop workflow before retiring it') unless stopped?
        @config.update_merge({'workflow'=>{'retired'=>retire}})
        @workflow_set.refresh_pointers
      end

      def retire_action(action_name)
        set_action_retired(action_name, retire: true)
      end

      def unretire_action(action_name)
        set_action_retired(action_name, retire: false)
      end

      private def set_action_retired(action_name, retire:)
        raise WorkflowConfigError, "Stop workflow before #{'un' unless retire}retiring action #{action_name.inspect}." unless stopped?

        valid_action   = @valid_action_configs.find { |ac| ac.action.name == action_name }
        retired_action = @retired_action_configs.find do |ac|
          if ac.respond_to? :action
            ac.action.name == action_name
          else
            ac['parameters'].find { |p| p['group'] == 'action' && p['name'] == 'name' && p['value'] == action_name }
          end
        end

        invalid_action = @invalid_bypassed_configs.find { |ac| ac.action.name == action_name }
        raise WorkflowConfigError, "Action #{action_name.inspect} does not exist for this workflow." unless valid_action || invalid_action || retired_action

        action_config =
          if retire
            raise WorkflowConfigError, "Action #{action_name.inspect} is already retired." if retired_action
            valid_action || invalid_action
          else
            raise WorkflowConfigError, "Action #{action_name.inspect} is not retired." unless retired_action
            retired_action
          end

        action_config.update_merge({'action'=>{'retired'=>retire}}, bypass_validation: true)

        load_action_configs
        @notify_to_refresh&.refresh
      end

      def unused_output_message
        unused = ''
        @unused_outputs.each { |docspec, action| unused = unused + (unused.empty? ? '' : ', ') + "#{docspec} from #{action}" }
        "Workflow has unused outputs: #{unused}"
      end

      def unused_output_docspec_check
        @config.workflow.unused_output_docspec_check
      end

      def unused_output_docspec_check=(val)
        return if val == unused_output_docspec_check
        raise(WorkflowConfigError, 'Must specify boolean value for unused_output_docspec_check') unless val == true || val == false
        raise(WorkflowConfigError, 'Stop workflow before changing unused_output_docspec_check') unless stopped?
        @check_unused_outputs = val
        raise(WorkflowConfigError, unused_output_message) if val && has_unused_output?
        @config.update_merge({'workflow'=>{'unused_output_docspec_check'=>val}})
        @workflow_set.refresh_pointers
      end

      def has_unused_output?
        return @unused_outputs.any? unless @check_unused_outputs
        @unused_outputs = Workflow.find_unused_output_docspecs(@valid_action_configs)
        @check_unused_outputs = false # no need to recheck unless config changes
        @unused_outputs.any?
      end

      def actions_valid?
        @invalid_action_configs.empty?
      end

      def valid?
        actions_valid? && @has_no_cycles
      end

      def run_mode
        @config.workflow.run_mode
      end

      def running?
        @config.workflow.run_mode == Armagh::Status::RUNNING
      end

      def stopping?
        @config.workflow.run_mode == Armagh::Status::STOPPING
      end

      def stopped?
        @config.workflow.run_mode == Armagh::Status::STOPPED
      end

      def run
        raise(WorkflowActivationError, 'Wait for workflow to stop before restarting' ) unless stopped?
        raise(WorkflowActivationError, 'Workflow not valid') unless valid?
        raise(WorkflowActivationError, unused_output_message) if has_unused_output?

        @logger.debug( "Running workflow #{@name}")

        callback_errors = []
        @valid_action_configs.each do |action_config|
          callback_error = action_config.test_and_return_errors
          next if callback_error.empty?
          error_string = ''
          callback_error.each do |method, error|
            error_string << ', ' unless error_string.empty?
            error_string << "#{method}: #{error}"
          end
          error_string = "Action #{action_config.action.name.inspect} failed #{error_string}"
          callback_errors << error_string
        end
        raise(WorkflowActivationError, callback_errors.join("\n")) unless callback_errors.empty?

        change_actions_active_status(true)
        @config.update_merge({'workflow'=>{'run_mode' => Armagh::Status::RUNNING}})
        @workflow_set.refresh_pointers
        status
      end

      def stop
        @logger.debug "Attempting to stop workflow #{@name}"
        return move_to_stopped if (!valid? && (running? || stopping?))

        documents_in_process = count_of_documents_in_process
        @logger.debug( "Trying to stop workflow #{@name}: #{documents_in_process} documents in process")

        if documents_in_process.zero? && !stopped?
          move_to_stopped
        else
          move_to_stopping if running?
          raise( WorkflowDocumentsInProcessError, "Cannot stop - #{documents_in_process} documents still processing")
        end
      end

      private def move_to_stopping

        raise(WorkflowActivationError, 'Workflow not running' ) unless running?

        @logger.debug( "Moving workflow #{@name} to stopping")
        change_actions_active_status( false, collect_actions_only: true )
        @config.update_merge( { 'workflow' => { 'run_mode' => Armagh::Status::STOPPING }} )
        @workflow_set.refresh_pointers
        status
      end

      private def move_to_stopped
        @logger.debug( "Stopping workflow #{@name}")
        change_actions_active_status( false )
        @config.update_merge( { 'workflow' => { 'run_mode' => Armagh::Status::STOPPED }} )
        @workflow_set.refresh_pointers
        status
      end

      def Workflow.actions_have_no_cycles?(action_configs)
        docspec_graph = Utils::TsortableHash.new
        action_configs.each do |config|
          config.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' }.each do |docspec_param|
            docspec = docspec_param.value
            docspec_graph[ config.input.docspec ] ||= []
            docspec_graph[ config.input.docspec ] << docspec
          end
        end
        begin
          docspec_graph.tsort
        rescue TSort::Cyclic
          return false
        end
        return true
      end

      def Workflow.find_unused_output_docspecs(action_configs)
        inputs  = {}
        outputs = {}
        action_configs.each do |config|
          inputs[config.input.docspec] = config.action.name
          config.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' }.each do |out_spec|
            outputs[out_spec.value] = config.action.name
          end
        end
        outputs.delete_if { |k, v| inputs.has_key?(k) }
      end

      private def change_actions_active_status( active, collect_actions_only: false )
        @valid_action_configs.reject{ |a| collect_actions_only && !(a.__type < Collect) }.each do |action_config|
          action_config.update_merge( { 'action' => { 'active' => active }} )
        end
      end

      def status
        alerts = Logging::Alert.get_counts( workflow: @name )

        {
          'name' => @name,
          'run_mode' => run_mode,
          'retired' => retired,
          'unused_output_docspec_check' => unused_output_docspec_check,
          'documents_in_process' => count_of_documents_in_process,
          'failed_documents'  => count_of_failed_documents,
          'valid' => valid?,
          'warn_alerts' => alerts[ 'warn' ],
          'error_alerts' => alerts[ 'error' ]
        }
      end

      def docspec_strings
        @valid_action_configs
          .collect{ |ac| ac.find_all_parameters{ |p| p.type == 'docspec' } }
          .flatten
          .collect{ |p| p.value.to_s }
          .sort
          .uniq
      end

      def failed_and_in_process_document_counts

        all_incomplete_docs = Armagh::Document.count_failed_and_in_process_documents_by_doctype
        my_docspec_strings = docspec_strings

        all_incomplete_docs.find_all{ |count_hash| my_docspec_strings.include?(count_hash['docspec_string'])}
      end

      def count_of_failed_documents
        failed_and_in_process_document_counts.collect{ |count_hash|
          count_hash['count'] if count_hash['category'] == 'failed'
        }.compact.sum
      end

      def count_of_documents_in_process
        failed_and_in_process_document_counts.collect{ |count_hash|
          count_hash['count'] if count_hash['category'] == 'in process'
        }.compact.sum
      end

      def valid_action_config_status( action_config )
        status = {
          'name'         => action_config.action.name,
          'valid'        => true,
          'active'       => action_config.action.active,
          'retired'      => action_config.action.retired,
          'last_updated' => action_config.__timestamp,
          'type'         => action_config.__type.to_s,
          'supertype'    => action_config.__type.superclass.to_s,
          'input_docspec' => action_config.input.docspec.to_s
        }
        if action_config.respond_to?(:output)
          status.merge!(
            'output_docspecs' => action_config.output.instance_variables.collect{ |iv|
              action_config.output.instance_variable_get(iv).to_s
            }.compact.flatten
          )
        end
        status
      end

      def invalid_action_config_status( invalid_action_config_hash )
        params = invalid_action_config_hash['parameters']
        {
          'name'         => params.find{|p| p['group']=='action' && p['name']=='name'}['value'],
          'valid'        => false,
          'active'       => params.find{|p| p['group']=='action' && p['name']=='active'}['value'],
          'retired'      => params.find{|p| p['group']=='action' && p['name']=='retired'}['value'],
          'last_updated' => '',
          'type'         => invalid_action_config_hash['type'].to_s,
          'supertype'    => invalid_action_config_hash['type'].superclass.to_s,
          'input_docspec' => params.find{|p| p['group']=='input' && p['name']=='docspec'}['value'].to_s,
          'output_docspecs' => params.collect{|p| p['value'].to_s if p['group']=='output' && p['type']=='docspec' && p['value'] }.compact
        }
      end

      def retired_action_config_status(retired_config)
        if retired_config.is_a? Hash
          invalid_action_config_status(retired_config)
        else
          valid_action_config_status(retired_config)
        end
      end

      def action_statuses(include_retired: false)
        statuses = []
        statuses.concat @valid_action_configs.collect{ |action_config| valid_action_config_status( action_config ) }
        statuses.concat @invalid_action_configs.collect{ |action_config_hash| invalid_action_config_status( action_config_hash)}
        statuses.concat @retired_action_configs.collect{ |retired_config| retired_action_config_status( retired_config ) } if include_retired
        statuses
      end

      def action_status(action_name)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
        return valid_action_config_status( valid_ac ) if valid_ac
        invalid_ac = @invalid_action_configs.find{ |config_hash|
          config_hash['parameters'].find{ |p| p['group']=='action' && p['name']=='name' && p['value']== action_name }
        }
        return invalid_action_config_status( invalid_ac ) if invalid_ac
        raise ActionFindError, "Workflow #{@name} has no #{action_name} action"
      end

      def type(action_name, include_retired: false)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
        valid_ac = @retired_action_configs.find{ |ac| ac.action.name == action_name } if include_retired && valid_ac.nil?
        return valid_ac.__type.name if valid_ac
        invalid_ac = @invalid_action_configs.find{ |config_hash|
          params = config_hash['parameters']
          params.find{ |p| p['group']=='action' && p['name']=='name' && p['value']== action_name }
        }
        return invalid_ac['type'] if invalid_ac
        raise ActionFindError, "Workflow #{@name} has no #{action_name} action"

      end

      def new_action_config( type )

        raise( WorkflowConfigError, 'Stop workflow before making changes' ) unless stopped?

        begin
          action_class = Actions.name_to_class(type)
        rescue => e
          raise ActionFindError, e.message
        end
        edit = {}
        edit['type'] = type
        edit['supertype'] = action_class.superclass.to_s
        edit['parameters'] = action_class.defined_parameters.collect{ |p| p.to_hash }
        append_valid_docstates_to_config( edit, action_class )
        wf_param = edit['parameters'].find{ |p| p['group'] == 'action' && p['name'] == 'workflow'}
        raise "Unable to set action config workflow parameter in #{type}" unless wf_param
        wf_param['value'] = @name
        edit
      end

      def edit_action_config(action_name, include_retired: false, bypass_validation: false)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
        valid_ac = @invalid_bypassed_configs.find{ |ac| ac.action.name == action_name } if bypass_validation && valid_ac.nil?
        valid_ac = @retired_action_configs.find{ |ac| ac.action.name == action_name } if include_retired && valid_ac.nil?
        if valid_ac
          edit = valid_ac.__type.edit_configuration( valid_ac.__values )
          append_valid_docstates_to_config( edit, valid_ac.__type )
          return edit
        end

        invalid_ac = @invalid_action_configs.find{ |config_hash|
          config_hash['parameters'].find{ |p| p['group']=='action' && p['name'] == 'name' && p['value'] == action_name }
        }
        if invalid_ac
          markup = invalid_ac
          append_valid_docstates_to_config( markup, markup['type'] )
          return markup
        end

        raise ActionFindError, "Workflow #{@name} has no #{action_name} action"
      end

      def get_action_config(action_name, include_retired: false, bypass_validation: false)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
        valid_ac = @invalid_bypassed_configs.find{ |ac| ac.action.name == action_name } if bypass_validation && valid_ac.nil?
        valid_ac = @retired_action_configs.find{ |ac| ac.action.name == action_name } if include_retired && valid_ac.nil?

        config = nil
        if valid_ac
          result = valid_ac.serialize
          config = result['values']
          config['type'] = result['type']
        end

        config
      end

      private def append_valid_docstates_to_config(config, action_class)
        input_docspec = config['parameters'].find{ |p| p['group'] == 'input' }
        input_docspec['valid_state'] = action_class::VALID_INPUT_STATE
        output_docspecs = config['parameters'].find_all{ |p| p['group'] == 'output' }
        output_docspecs.each do |output_docspec|
          output_docspec['valid_states'] = action_class::VALID_OUTPUT_STATES
        end
      end

    end
  end
end
