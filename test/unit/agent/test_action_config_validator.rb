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

require_relative '../../../lib/environment.rb'
Armagh::Environment.init

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/configuration/action_config_validator'

require 'test/unit'
require 'mocha/test_unit'

class TestPublisher < Armagh::Actions::Publish
  define_parameter(name: 'arg', description: 'Description', type: String)
end

class TestConsumer < Armagh::Actions::Consume
  define_parameter(name: 'arg', description: 'Description', type: String)
end

class TestDivider < Armagh::Actions::Divide; end
class BadAction < Armagh::Actions::Action; end
class TestCollector < Armagh::Actions::Collect; end
class TestSplitter < Armagh::Actions::Split; end

class TestActionConfigValidator < Test::Unit::TestCase
  def setup
    @action_config_validator = Armagh::Configuration::ActionConfigValidator.new
  end

  def valid_configuration
    {
        'publisher' => {
            'doc_type' => 'CollectedDocument',
            'action_class_name' => 'TestPublisher',
            'parameters' => {'arg' => 'value'}
        },
        'consumer' => {
            'input_doc_type' => 'CollectedDocument',
            'action_class_name' => 'TestConsumer',
            'output_docspecs' => {},
            'parameters' => {'arg' => 'value'}
        },
        'splitter' => {
            'input_doc_type' => 'CollectedDocumentRaw',
            'action_class_name' => 'TestSplitter',
            'output_docspecs' => {
                'raw_collected' => {'type' => 'CollectedDocument', 'state' => 'working'},
                'raw_ready' => {'type' => 'CollectedDocument', 'state' => 'ready'}
            },
            'parameters' => {}
        },
        'collector' => {
            'input_doc_type' => 'TriggerDocument',
            'output_docspecs' => {
                'collect_output_with_divide' => {'type' => 'CollectedDocument', 'state' => 'working',
                                                 'divider' => {
                                                     'divider_class_name' => 'TestDivider',
                                                     'parameters' => {}
                                                 }},
                'collect_output_no_divide' => {'type' => 'CollectedDocumentRaw', 'state' => 'ready'}
            },
            'action_class_name' => 'TestCollector',
            'parameters' => {}
        }
    }
  end

  def test_validate
    config = valid_configuration
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']
    assert_empty result['warnings']
  end

  def test_validate_empty_configuration
    config = {}
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']
    assert_include result['warnings'], 'Action Configuration is empty.'
  end

  def test_validate_invalid_action
    config = valid_configuration
    config['invalid_action'] = 'invalid_action'
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?
    assert_include result['errors'], "Action 'invalid_action' needs to be a Hash.  Was a String."
    assert_empty result['warnings']
  end

  def test_validate_extra_field
    config = valid_configuration
    config['publisher']['extra_field'] = 'extra'
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']
    assert_include result['warnings'], "Action 'publisher' has the following unexpected fields: [\"extra_field\"]."
  end

  def test_validate_missing_action_fields
    config = valid_configuration
    config['publisher'].delete('doc_type')
    config['consumer'].delete('action_class_name')
    config['splitter'].delete('output_docspecs')
    config['splitter'].delete('input_doc_type')
    config['collector'].delete('parameters')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'publisher' needs a 'doc_type' field if it is a PublishAction or an 'input_doc_type' and 'output_docspecs' field if it is any other action type.",
        "Action 'splitter' needs a 'doc_type' field if it is a PublishAction or an 'input_doc_type' and 'output_docspecs' field if it is any other action type.",
        "Action 'collector' does not have 'parameters'.",
        "Action 'consumer' does not have 'action_class_name'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_empty_doc_type
    config = valid_configuration
    config['publisher']['doc_type'] = ''
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'publisher' 'doc_type' has an error: Type must be a non-empty string.'",
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_empty_input_doc_type
    config = valid_configuration
    config['splitter']['input_doc_type'] = ''
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'splitter', 'input_doc_type' has an error: Type must be a non-empty string.'"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_empty_docspec_type
    config = valid_configuration
    config['splitter']['output_docspecs']['raw_ready']['type'] = ''
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'splitter', docspec 'raw_ready' has an error: Type must be a non-empty string.'"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_missing_docspec_fields
    config = valid_configuration
    config['splitter']['output_docspecs']['raw_ready'].delete('state')
    config['splitter']['output_docspecs']['raw_collected'].delete('type')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'splitter', docspec 'raw_collected' does not have 'type'.",
        "Action 'splitter', docspec 'raw_ready' does not have 'state'.",
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_missing_divider_fields
    config = valid_configuration
    config['collector']['output_docspecs']['collect_output_with_divide']['divider'].delete('divider_class_name')
    config['collector']['output_docspecs']['collect_output_with_divide']['divider'].delete('parameters')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'collector', docspec 'collect_output_with_divide' divider does not have 'parameters'.",
        "Action 'collector', docspec 'collect_output_with_divide' divider does not have 'divider_class_name'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_wrong_divider_type
    config = valid_configuration
    config['collector']['output_docspecs']['collect_output_with_divide']['divider'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'collector', docspec 'collect_output_with_divide' divider must be a 'Hash'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_action_fields
    config = valid_configuration
    config['publisher']['doc_type'] = 123
    config['consumer']['action_class_name'] = Random.new
    config['splitter']['output_docspecs'] = Random.new
    config['splitter']['input_doc_type'] = Random.new
    config['collector']['parameters'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Doc type '123' from 'publisher' must be a 'String'.  It is a 'Fixnum'.",
        "Field 'action_class_name' from action 'consumer' must be a 'String'.  It is a 'Random'.",
        "Field 'parameters' from action 'collector' must be a 'Hash'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_doctype_fields
    config = valid_configuration
    config['splitter']['output_docspecs']['raw_ready']['state'] = Random.new
    config['splitter']['output_docspecs']['raw_collected']['type'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Field 'state' from action 'splitter', docspec 'raw_ready' must be a 'String'.  It is a 'Random'.",
        "Field 'type' from action 'splitter', docspec 'raw_collected' must be a 'String'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_divider_fields
    config = valid_configuration
    config['collector']['output_docspecs']['collect_output_with_divide']['divider']['divider_class_name'] = Random.new
    config['collector']['output_docspecs']['collect_output_with_divide']['divider']['parameters'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Field 'parameters' from action 'collector', docspec 'collect_output_with_divide' divider must be a 'Hash'.  It is a 'Random'.",
        "Field 'divider_class_name' from action 'collector', docspec 'collect_output_with_divide' divider must be a 'String'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_bad_action
    config = valid_configuration
    config.merge! ({
        'bad_action' => {
            'input_doc_type' => 'CollectedDocument',
            'action_class_name' => 'BadAction',
            'output_docspecs' => {},
            'parameters' => {}
        }
    })

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Class 'BadAction' from action 'bad_action' is not a CollectAction, SplitAction, PublishAction, or ConsumeAction."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_non_existing_action
    config = valid_configuration
    config.merge! ({
        'bad_action' => {
            'input_doc_type' => 'CollectedDocument',
            'action_class_name' => 'NotAnAction',
            'output_docspecs' => {},
            'parameters' => {}
        }
    })

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Class 'NotAnAction' from action 'bad_action' does not exist."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_in_out_same
    config = valid_configuration
    config['splitter']['input_doc_type'] = 'CollectedDocument'
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Input doctype and output docspec 'raw_collected' from action 'splitter' are the same but they must be different.",
        "Input doctype and output docspec 'raw_ready' from action 'splitter' are the same but they must be different."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_non_publisher_produce_published
    config = valid_configuration
    config['splitter']['output_docspecs']['raw_ready']['state'] = 'published'
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'splitter' error: Output docspec 'raw_ready' state must be one of: [\"ready\", \"working\"]."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_action_validation_called
    config = valid_configuration

    validate_result = {
        'valid' => 'false',
        'warnings' => ['warn'],
        'errors' => ['err']
    }

    TestCollector.any_instance.expects(:validate).once.returns(validate_result)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' error: err"
    ]

    expected_warnings = [
        "Action 'collector' warning: warn"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_equal expected_warnings.sort, result['warnings'].sort
  end

  def test_action_validation_failed
    config = valid_configuration
    error = RuntimeError.new 'ERROR'
    TestCollector.any_instance.expects(:validate).once.raises(error)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' validation failed: ERROR"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_divider_validation_called
    config = valid_configuration

    validate_result = {
        'valid' => 'false',
        'warnings' => ['warn'],
        'errors' => ['err']
    }

    TestDivider.any_instance.expects(:validate).once.returns(validate_result)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' divider error: err"
    ]

    expected_warnings = [
        "Action 'collector' divider warning: warn"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_equal expected_warnings.sort, result['warnings'].sort
  end

  def test_divider_validation_failed
    config = valid_configuration
    error = RuntimeError.new 'ERROR'
    TestDivider.any_instance.expects(:validate).once.raises(error)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' divider validation failed: ERROR"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_shared_docspec_splitter_publisher
    config = valid_configuration
    config['publisher']['doc_type'] = config['splitter']['input_doc_type']

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Input docspec 'CollectedDocumentRaw:ready' cannot be shared between multiple actions.  Shared by: [\"publisher\", \"splitter\"]"
    ]
    assert_equal expected_errors.sort, result['errors'].sort
  end

  def test_shared_docspec_splitters
    config = valid_configuration
    config['splitter2'] = {
        'input_doc_type' => config['splitter']['input_doc_type'],
        'action_class_name' => 'TestSplitter',
        'output_docspecs' => {
            'raw_collected' => {'type' => 'CollectedDocument', 'state' => 'working'},
            'raw_ready' => {'type' => 'CollectedDocument', 'state' => 'ready'}
        },
        'parameters' => {}
    }

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Input docspec 'CollectedDocumentRaw:ready' cannot be shared between multiple actions.  Shared by: [\"splitter\", \"splitter2\"]"
    ]
    assert_equal expected_errors.sort, result['errors'].sort
  end

  def test_shared_docspec_publishers
    config = valid_configuration
    config['publisher2'] = {
        'doc_type' => 'CollectedDocument',
        'action_class_name' => 'TestPublisher',
        'parameters' => {}
    }

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Input docspec 'CollectedDocument:ready' cannot be shared between multiple actions.  Shared by: [\"publisher\", \"publisher2\"]"
    ]
    assert_equal expected_errors.sort, result['errors'].sort
  end

  def test_shared_doscpec_only_consumers
    config = valid_configuration

    config['consumer2'] = {
        'input_doc_type' => config['consumer']['input_doc_type'],
        'action_class_name' => 'TestConsumer',
        'output_docspecs' => {},
        'parameters' => {'arg' => 'value'}
    }

    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']
    assert_empty result['warnings']
  end

  def test_docspec_not_ingested
    config = valid_configuration
    config['consumer']['output_docspecs'] = {'unused_spec' => {'type' => 'UnusedType', 'state' => 'ready'}}
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']

    expected_warnings = [
        "Actions [\"consumer\"] produce docspec 'UnusedType:ready', but no action takes that docspec as input."
    ]
    assert_equal expected_warnings.sort, result['warnings'].sort
  end

  def test_docspec_working_not_ingested
    config = valid_configuration
    config['consumer']['output_docspecs'] = {'unused_spec' => {'type' => 'UnusedType', 'state' => 'working'}}
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']
    assert_not_includes result['warnings'], "Actions [\"consumer\"] produce docspec 'UnusedType:working', but no action takes that docspec as input."
  end

  def test_working_not_used
    config = valid_configuration
    config['consumer']['output_docspecs'] = {'unused_spec' => {'type' => 'UnusedType', 'state' => 'working'}}
    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']

    expected_warnings = [
        "No actions convert 'UnusedType' from a working to a ready state."
    ]
    assert_equal expected_warnings.sort, result['warnings'].sort
  end

  def test_loops
    config = valid_configuration
    config['consumer']['output_docspecs'] = {'loop_spec' => {'type' => 'CollectedDocumentRaw', 'state' => 'ready'}}
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        'Action configuration has a cycle.'
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validation_unexpected_param
    config = valid_configuration
    config['consumer']['parameters']['unknown'] = 'something'

    result = @action_config_validator.validate(config)
    assert_true result['valid'], result['errors']
    assert_false @action_config_validator.error?
    assert_empty result['errors']

    expected_warnings = [
        "Action 'consumer' warning: Parameter 'unknown' not defined for class TestConsumer."
    ]
    assert_equal expected_warnings.sort, result['warnings'].sort
  end
end