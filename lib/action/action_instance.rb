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

require 'armagh/action_document'

module Armagh

  # An action to perform on a document
  class ActionInstance
    attr_reader :name, :input_doctype, :output_doctype, :action_class_name

    def initialize(name, input_doctype, output_doctype, caller, logger, config, action_class_name)
      @name = name
      @input_doctype = input_doctype
      @output_doctype = output_doctype
      @action_class_name = action_class_name
      @action_class_instance = Object::const_get(action_class_name).new(caller, logger, config)
    end

    def execute(document)
      action_doc = ActionDocument.new(document.content, document.meta, document.state)
      @action_class_instance.execute(action_doc)
    end

    def ==(other)
      @name == other.name && @input_doctype == other.input_doctype && @output_doctype == other.output_doctype && @action_class_name == other.action_class_name
    end
  end
end
