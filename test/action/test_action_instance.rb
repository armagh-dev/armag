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

require_relative '../test_helpers/coverage_helper'
require_relative '../../lib/action/action_instance'

require 'armagh/action'

require 'test/unit'
require 'mocha/test_unit'


class TestAction < Armagh::Action
  OUT_CONTENT = 'output content'
  OUT_META = 'output meta'

  def execute(content, meta)
    [OUT_CONTENT, OUT_META]
  end
end

class TestActionInstance < Test::Unit::TestCase

  def setup
    @name = 'name'
    @input_doctype = 'input doctype'
    @output_doctype = 'output_doctype'
    @action_class_name = 'TestAction'
    @caller = mock 'agent'
    @logger = mock 'logger'
    @config = {}
    @action_instance = Armagh::ActionInstance.new(@name, @input_doctype, @output_doctype, @caller, @logger, @config, @action_class_name)
  end

  def test_name
    assert_equal(@name, @action_instance.name)
  end

  def test_input_doctype
    assert_equal(@input_doctype, @action_instance.input_doctype)
  end

  def test_output_doctype
    assert_equal(@output_doctype, @action_instance.output_doctype)
  end

  def test_action_class_name
    assert_equal(@action_class_name, @action_instance.action_class_name)
  end

  def test_execute
    doc = stub({:content => nil, :meta => nil})
    content, meta = @action_instance.execute(doc)
    assert_equal(TestAction::OUT_CONTENT, content)
    assert_equal(TestAction::OUT_META, meta)
  end

end