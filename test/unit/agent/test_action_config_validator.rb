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

require_relative '../../helpers/coverage_helper'

require_relative '../../../lib/configuration/action_config_validator'
require_relative '../action/test_action_manager'

require 'test/unit'

class TestPublisher < Armagh::PublishAction; end
class TestCollector < Armagh::CollectAction; end
class TestParser < Armagh::ParseAction; end
class TestSubscriber < Armagh::SubscribeAction; end
class TestSplitter < Armagh::CollectionSplitter; end
class BadAction < Armagh::Action; end

class TestActionConfigValidator < Test::Unit::TestCase

  def setup
    @action_config_validator = Armagh::Configuration::ActionConfigValidator.new

    @test_action_manager = TestActionManager.new(nil)
    @test_action_manager.setup
  end

  def valid_configuration
    {
        'publisher' => {
            'doc_type' => 'CollectedDocument',
            'action_class_name' => 'TestPublisher',
            'parameters' => {'arg' => 'value'}
        },
        'subscriber' => {
            'input_doc_type' => 'CollectedDocument',
            'action_class_name' => 'TestSubscriber',
            'output_docspecs' => {},
            'parameters' => {'arg' => 'value'}
        },
        'parser' => {
            'input_doc_type' => 'CollectedDocumentRaw',
            'action_class_name' => 'TestParser',
            'output_docspecs' => {
                'raw_collected' => {'type' => 'CollectedDocument', 'state' => 'working'},
                'raw_ready' => {'type' => 'CollectedDocument', 'state' => 'ready'}
            },
            'parameters' => {}
        },
        'collector' => {
            'input_doc_type' => 'TriggerDocument',
            'output_docspecs' => {
                'collect_output_with_split' => {'type' => 'CollectedDocument', 'state' => 'working',
                                                'splitter' => {
                                                    'splitter_class_name' => 'TestSplitter',
                                                    'parameters' => {}
                                                }},
                'collect_output_no_split' => {'type' => 'CollectedDocumentRaw', 'state' => 'ready'}
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
    config['subscriber'].delete('action_class_name')
    config['parser'].delete('output_docspecs')
    config['parser'].delete('input_doc_type')
    config['collector'].delete('parameters')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'publisher' needs a 'doc_type' field if it is a PublishAction or an 'input_doc_type' and 'output_docspecs' field if it is any other action type.",
        "Action 'parser' needs a 'doc_type' field if it is a PublishAction or an 'input_doc_type' and 'output_docspecs' field if it is any other action type.",
        "Action 'collector' does not have  'parameters'.",
        "Action 'subscriber' does not have  'action_class_name'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_missing_docspec_fields
    config = valid_configuration
    config['parser']['output_docspecs']['raw_ready'].delete('state')
    config['parser']['output_docspecs']['raw_collected'].delete('type')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'parser', docspec 'raw_collected' does not have 'type'.",
        "Action 'parser', docspec 'raw_ready' does not have 'state'.",
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_missing_splitter_fields
    config = valid_configuration
    config['collector']['output_docspecs']['collect_output_with_split']['splitter'].delete('splitter_class_name')
    config['collector']['output_docspecs']['collect_output_with_split']['splitter'].delete('parameters')

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'collector', docspec 'collect_output_with_split' splitter does not have 'parameters'.",
        "Action 'collector', docspec 'collect_output_with_split' splitter does not have 'splitter_class_name'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_action_fields
    config = valid_configuration
    config['publisher']['doc_type'] = 123
    config['subscriber']['action_class_name'] = Random.new
    config['parser']['output_docspecs'] = Random.new
    config['parser']['input_doc_type'] = Random.new
    config['collector']['parameters'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Doc type '123' from 'publisher' must be a 'String'.  It is a 'Fixnum'.",
        "Field 'action_class_name' from action 'subscriber' must be a 'String'.  It is a 'Random'.",
        "Field 'parameters' from action 'collector' must be a 'Hash'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_doctype_fields
    config = valid_configuration
    config['parser']['output_docspecs']['raw_ready']['state'] = Random.new
    config['parser']['output_docspecs']['raw_collected']['type'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Field 'state' from action 'parser', docspec 'raw_ready' must be a 'String'.  It is a 'Random'.",
        "Field 'type' from action 'parser', docspec 'raw_collected' must be a 'String'.  It is a 'Random'."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_wrong_splitter_fields
    config = valid_configuration
    config['collector']['output_docspecs']['collect_output_with_split']['splitter']['splitter_class_name'] = Random.new
    config['collector']['output_docspecs']['collect_output_with_split']['splitter']['parameters'] = Random.new

    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Field 'parameters' from action 'collector', docspec 'collect_output_with_split' splitter must be a 'Hash'.  It is a 'Random'.",
        "Field 'splitter_class_name' from action 'collector', docspec 'collect_output_with_split' splitter must be a 'String'.  It is a 'Random'."
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
        "Class 'BadAction' from action 'bad_action' is not a CollectAction, ParseAction, PublishAction, or SubscribeAction."
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
    config['parser']['input_doc_type'] = 'CollectedDocument'
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Input doctype and output docspec 'raw_collected' from action 'parser' are the same but they must be different.",
        "Input doctype and output docspec 'raw_ready' from action 'parser' are the same but they must be different."
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  def test_validate_non_publisher_produce_published
    config = valid_configuration
    config['parser']['output_docspecs']['raw_ready']['state'] = 'published'
    result = @action_config_validator.validate(config)
    assert_false result['valid'], result['errors']
    assert_true @action_config_validator.error?

    expected_errors = [
        "Action 'parser' error: Output docspec 'raw_ready' state must be one of: [\"ready\", \"working\"]."
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

  def test_splitter_validation_called
    config = valid_configuration

    validate_result = {
        'valid' => 'false',
        'warnings' => ['warn'],
        'errors' => ['err']
    }

    TestSplitter.any_instance.expects(:validate).once.returns(validate_result)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' splitter error: err"
    ]

    expected_warnings = [
        "Action 'collector' splitter warning: warn"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_equal expected_warnings.sort, result['warnings'].sort
  end

  def test_splitter_validation_failed
    config = valid_configuration
    error = RuntimeError.new 'ERROR'
    TestSplitter.any_instance.expects(:validate).once.raises(error)

    result = @action_config_validator.validate(config)
    assert_true @action_config_validator.error?
    expected_errors = [
        "Action 'collector' splitter validation failed: ERROR"
    ]

    assert_equal expected_errors.sort, result['errors'].sort
    assert_empty result['warnings']
  end

  # TODO JBOWES Workflow Validation Testing
  # * [DONE] A given input docspec can only be shared by multiple subscribers
  # * [DONE] Warn when docspecs arent used (produces ready but nothing ingests that doc type)
  # * [DONE] Warn when docspecs arent used (produces working but no parser produces ready for a given doctype)
  # * [DONE] Warn duplicate docspecs (THIS MAY HAVE BEEN REMOVED)
  # * [DONE] Check for loops (error)

  # TODO JBOWES - Test coverage.  Some of the code may not be reachable due to earlier checks, and should therefore be removed

end