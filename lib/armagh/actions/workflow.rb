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

module Armagh
  module Actions

    class WorkflowInitError < StandardError; end
    class WorkflowConfigError < StandardError; end
    class WorkflowActivationError < StandardError; end
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
      attr_reader :name, :valid_action_configs, :invalid_action_configs, :actions, :has_no_cycles

      define_parameter name: 'run_mode', type: 'string', description: 'run, finish, or stop', required: true, default: 'stop', group: 'workflow'
      define_parameter name: 'retired',  type: 'boolean', description: 'not normally displayed', required: true, default: false, group: 'workflow'
      define_parameter name: 'unused_output_docspec_check', type: 'boolean', description: 'verify that there are no unused output docspecs', required: true, default: true, group: 'workflow'
      define_group_validation_callback callback_class: Workflow, callback_method: 'check_run_mode'

      def self.check_run_mode(candidate_config)
        error = nil
        good_run_modes = %w(run finish stop)
        unless good_run_modes.include? candidate_config.workflow.run_mode
          error = "run_mode must be one of: #{good_run_modes}"
        end
        error
      end

      def self.create( config_store, name, notify_to_refresh: nil )
        workflow_config = create_configuration(config_store, name, {}, maintain_history:true )
        new(config_store, name, workflow_config, notify_to_refresh: notify_to_refresh )
      rescue WorkflowInitError, Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      def self.edit_configuration( config_values, creating_in: )
        edit = super( config_values )
        name = config_values.dig('workflow','name')
        if creating_in && name && find( creating_in, name)
          raise WorkflowConfigError, 'Workflow name already in use'
        end
        edit
      end

      def self.find( config_store, name, notify_to_refresh: nil )
        raise WorkflowConfigError, 'create requires a workflow name' if name.nil? || name.empty?
        workflow_config = find_configuration( config_store, name )
        if workflow_config
          new(config_store, name, workflow_config, notify_to_refresh: notify_to_refresh )
        end
      rescue Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      def self.find_all( config_store, notify_to_refresh: nil )
        raise WorkflowConfigError, 'notify_to_refresh must respond to :refresh' unless notify_to_refresh && notify_to_refresh.respond_to?(:refresh)
        workflows = []

        workflow_configs = find_all_configurations( config_store )
        workflow_configs.each do |_klass,workflow_config|
          name = workflow_config.__name
          workflows << new(config_store, name, workflow_config, notify_to_refresh: notify_to_refresh )
        end
        workflows
      rescue Configh::ConfigInitError => e
        raise WorkflowConfigError, e.message
      end

      private_class_method :new

      def initialize(config_store, name, config_object, notify_to_refresh: nil )

        raise WorkflowInitError, 'name cannot be nil' if name.nil? || name.empty?
        raise WorkflowInitError, 'notify_to_refresh must respond to :refresh' unless notify_to_refresh.nil? || notify_to_refresh.respond_to?(:refresh)

        @config_store = config_store
        @name = name
        @config = config_object
        @notify_to_refresh = notify_to_refresh
        @valid_action_configs = []
        @invalid_action_configs = []
        @has_no_cycles = true
        @check_unused_outputs = unused_output_docspec_check
        @unused_outputs = {}
        load_action_configs
      end

      def create_action_config( type, cand_config_values )
        update_action_config( type, cand_config_values, creating:true )
      end

      def update_action_config( type, cand_config_values, creating: false)

        raise( WorkflowConfigError, 'Stop workflow before making changes' ) unless run_mode == 'stop'

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
            config = action_class.create_configuration(@config_store, cand_action_name, cand_config_values, maintain_history: true  )
          else
            config = action_class.force_update_configuration(@config_store, cand_action_name, cand_config_values, maintain_history: true  )
          end
          load_action_configs
          @notify_to_refresh&.refresh
          config
        rescue Configh::ConfigInitError => e
          config_with_errors = action_class.edit_configuration(cand_config_values)
          if e.message == 'Name already in use'
            action_name_config = config_with_errors['parameters'].find{ |p_config| p_config['group'] == 'action' and p_config['name'] == 'name' }
            action_name_config['error'] = 'already in use' if action_name_config
          end
          raise ActionConfigError.new("Configuration has errors: #{e.message}", config_with_errors)
        rescue Configh::ConfigValidationError => e
          config_with_errors = action_class.edit_configuration(cand_config_values)
          raise ActionConfigError.new("Configuration has errors: #{e.message}",config_with_errors)
        end
      end

      def load_action_configs
        @valid_action_configs = []
        @invalid_action_configs = []

        Action.find_all_configurations(@config_store, include_descendants:true, raw:true)
          .each do |klass, raw_action_config|
          if raw_action_config['values'].dig('action','workflow') == @name
            if klass.configuration_values_valid?(raw_action_config['values'])
              @valid_action_configs << klass.find_configuration(@config_store, raw_action_config['name'])
            else
              @invalid_action_configs << klass.edit_configuration(raw_action_config['values'])
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
        raise(WorkflowConfigError, 'Stop workflow before retiring it') unless run_mode == 'stop'
        @config.update_merge({'workflow'=>{'retired'=>retire}})
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
        raise(WorkflowConfigError, 'Stop workflow before changing unused_output_docspec_check') unless run_mode == 'stop'
        @check_unused_outputs = val
        raise(WorkflowConfigError, unused_output_message) if val && has_unused_output?
        @config.update_merge({'workflow'=>{'unused_output_docspec_check'=>val}})
        @notify_to_refresh&.refresh
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
        @config.workflow.run_mode == 'run'
      end

      def run
        raise(WorkflowActivationError, 'Wait for workflow to stop before restarting' ) unless run_mode == 'stop'
        raise(WorkflowActivationError, 'Workflow not valid') unless valid?
        raise(WorkflowActivationError, unused_output_message) if has_unused_output?

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
        @config.update_merge({'workflow'=>{'run_mode' => 'run'}})

        @notify_to_refresh&.refresh
        status
      end

      #TODO - This method is intended to stop collection so we can finish processing out
      # this workflow.  Just setting the collect action inactive isn't enough - what
      # if there's a collect doc sitting out there, or one that's been picked up by
      # an agent, we could have a race condition.
      def finish
        raise(WorkflowActivationError, 'Workflow not valid') unless valid?
        raise(WorkflowActivationError, 'Workflow not running' ) unless run_mode == 'run'

        change_actions_active_status( false, collect_actions_only: true )
        @config.update_merge( { 'workflow' => { 'run_mode' => 'finish' }} )
        @notify_to_refresh&.refresh
        status
      end

      def stop
        raise( WorkflowActivationError, 'Workflow not valid' ) unless valid?

        if @config.workflow.run_mode == 'run'
          finish
        else
          num_docs = doc_counts.inject(0){|r,n| r+n}
          if num_docs == 0
            change_actions_active_status( false )
            @config.update_merge( { 'workflow' => { 'run_mode' => 'stop' }} )
            @notify_to_refresh&.refresh
            status
          else
            raise( WorkflowActivationError, "Cannot stop - #{num_docs} documents still processing")
          end
        end
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
        working_docs_count, failed_docs_count, published_pending_consume_docs_count = doc_counts

        valid = true
        action_statuses.each { |action| valid = false unless action['valid'] }

        {
          'name' => @name,
          'run_mode' => run_mode,
          'retired' => retired,
          'unused_output_docspec_check' => unused_output_docspec_check,
          'working_docs_count' => working_docs_count,
          'failed_docs_count'  => failed_docs_count,
          'published_pending_consume_docs_count' => published_pending_consume_docs_count,
          'docs_count' => working_docs_count + failed_docs_count + published_pending_consume_docs_count,
          'valid' => valid
        }
      end

      def produced_docspec_names
        @valid_action_configs
          .collect{ |ac| ac.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' } }
          .flatten
          .collect{ |p| p.value.to_s }
      end

      def published_doctypes
        @valid_action_configs
          .select{ |ac| ac.__type < Publish }
          .collect{ |ac| ac.find_all_parameters{ |p| p.group == 'output' and p.type == 'docspec' } }
          .flatten
          .collect{ |p| p.value.type }.sort.uniq
      end

      def doc_counts
        all_docs = Armagh::Document.count_incomplete_by_doctype( published_doctypes )

        working_docs_count = 0
        all_docs['documents'].each do |counted_docspec_name, count|
          working_docs_count += count if produced_docspec_names.include?(counted_docspec_name)
        end
        failed_docs_count  = 0
        all_docs['failures'].each do |counted_docspec_name, count|
          failed_docs_count += count if produced_docspec_names.include?(counted_docspec_name)
        end
        published_pending_consume_docs_count = 0
        other_collections = all_docs.keys - [ 'documents', 'failures' ]
        other_collections.each do |coll|
          all_docs[ coll ].each do |counted_docspec_name, count|
            published_pending_consume_docs_count += count if produced_docspec_names.include?(counted_docspec_name)
          end
        end
        [ working_docs_count, failed_docs_count, published_pending_consume_docs_count ]
      end

      def valid_action_config_status( action_config )
        status = {
          'name'         => action_config.action.name,
          'valid'        => true,
          'active'       => action_config.action.active,
          'last_updated' => action_config.__timestamp,
          'type'         => action_config.__type.to_s,
          'supertype'    => action_config.__type.superclass.to_s,
          'input_docspec' => action_config.input.docspec.to_s,
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
          'last_updated' => '',
          'type'         => invalid_action_config_hash['type'].to_s,
          'supertype'    => invalid_action_config_hash['type'].superclass.to_s,
          'input_docspec' => params.find{|p| p['group']=='input' && p['name']=='docspec'}['value'].to_s,
          'output_docspecs' => params.collect{|p| p['value'].to_s if p['group']=='output' && p['type']=='docspec' && p['value'] }.compact
        }

      end

      def action_statuses
        statuses = []
        statuses.concat @valid_action_configs.collect{ |action_config| valid_action_config_status( action_config ) }
        statuses.concat @invalid_action_configs.collect{ |action_config_hash| invalid_action_config_status( action_config_hash)}
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

      def type(action_name)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
        return valid_ac.__type.name if valid_ac
        invalid_ac = @invalid_action_configs.find{ |config_hash|
          params = config_hash['parameters']
          params.find{ |p| p['group']=='action' && p['name']=='name' && p['value']== action_name }
        }
        return invalid_ac['type'] if invalid_ac
        raise ActionFindError, "Workflow #{@name} has no #{action_name} action"

      end

      def new_action_config( type )

        raise( WorkflowConfigError, 'Stop workflow before making changes' ) unless run_mode == 'stop'

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

      def edit_action_config(action_name)

        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
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

      def get_action_config(action_name)
        valid_ac = @valid_action_configs.find{ |ac| ac.action.name == action_name }
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
