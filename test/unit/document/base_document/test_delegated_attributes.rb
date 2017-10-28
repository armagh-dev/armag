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
require_relative '../../../helpers/coverage_helper'

require_relative '../../../../lib/armagh/document/base_document/delegated_attributes'

require 'test/unit'
require 'mocha/test_unit'


class TestDelegatedAttributes < Test::Unit::TestCase

  def setup_class
    @klass = Object.const_set( "TDAUnitTestClass", Class.new )
    @klass.include Armagh::BaseDocument::DelegatedAttributes
    @klass.send :attr_accessor, :image, :flag, :alt_image
    @klass.send( :define_method, :initialize) {
      @image = {}
      @alt_image = {}
      @flag = false
    }
    @klass.send( :define_method, :adds_one){ |x| x + 1 }
    @klass.send( :define_method, :set_flag){ |x| @flag=true if [42,[42].include?(x)]}
    @klass.send( :define_method, :stringize){ |x| x.to_s }
    @klass.send( :define_method, :stringize_ary){ |ary| ary.collect(&:to_s)}
  end
  def setup
    setup_class
  end

  def test_delegated_attr_accessor
    TDAUnitTestClass.delegated_attr_accessor :my_attr
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 42, obj.my_attr
    assert_equal 42, obj.image[ 'my_attr' ]
  end

  def test_delegated_attr_accessor_with_key
    TDAUnitTestClass.delegated_attr_accessor :my_attr, :stored_as
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 42, obj.my_attr
    assert_equal 42, obj.image[ 'stored_as' ]
    assert_false obj.image.has_key? 'my_attr'
    obj.delete_my_attr
    assert_false obj.image.has_key? 'stored_as'
  end

  def test_delegated_attr_accessor_validates_with
    TDAUnitTestClass.delegated_attr_accessor :my_attr, validates_with: :adds_one
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 43, obj.my_attr
    assert_equal 43, obj.image[ 'my_attr' ]
  end

  def test_delegated_attr_accessor_validates_with_self_access
    TDAUnitTestClass.delegated_attr_accessor :some_flag_attr
    TDAUnitTestClass.send( :define_method, :check_the_flag) { |value| some_flag_attr ? "yay" : "boo" }
    TDAUnitTestClass.delegated_attr_accessor :my_attr, validates_with: :check_the_flag

    obj = TDAUnitTestClass.new
    obj.some_flag_attr = true
    obj.my_attr = 'go for it!'
    assert_equal 'yay', obj.my_attr
  end

  def test_delegated_attr_accessor_with_key_validates_with
    TDAUnitTestClass.delegated_attr_accessor :my_attr, :stored_as, validates_with: :adds_one
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 43, obj.my_attr
    assert_equal 43, obj.image[ 'stored_as' ]
    assert_false obj.image.has_key? 'my_attr'
  end

  def test_delegated_attr_accessor_after_change
    TDAUnitTestClass.delegated_attr_accessor :my_attr, after_change: :set_flag
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 42, obj.my_attr
    assert_true obj.flag
  end

  def test_delegated_attr_accessor_after_return
    TDAUnitTestClass.delegated_attr_accessor :my_attr, after_return: :stringize
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal "42", obj.my_attr
    assert_equal 42, obj.image[ 'my_attr' ]
  end

  def test_delegated_attr_accessor_with_key_after_return
    TDAUnitTestClass.delegated_attr_accessor :my_attr, :stored_as, after_return: :stringize
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal "42", obj.my_attr
    assert_equal 42, obj.image[ 'stored_as' ]
  end

  def test_delegated_attr_accessor_delegates_to
    TDAUnitTestClass.delegated_attr_accessor :my_attr, delegates_to: :@alt_image
    obj = TDAUnitTestClass.new
    obj.my_attr = 42
    assert_equal 42, obj.my_attr
    assert_equal 42, obj.alt_image[ 'my_attr' ]
    assert_false obj.image.has_key?( 'my_attr' )
  end

  def test_delegated_attr_accessor_references_class
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs(internal_id: 123)

    TDAUnitTestClass.delegated_attr_accessor :my_account, references_class: Account
    obj = TDAUnitTestClass.new
    Account.expects(:get).with(123).returns(a)
    obj.my_account = 123
    assert_equal a, obj.my_account
    assert_equal 123, obj.image[ 'my_account' ]
  end

  def test_delegated_attr_accessor_references_class_assign_object
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs(internal_id: 123)

    TDAUnitTestClass.delegated_attr_accessor :my_account, references_class: Account
    obj = TDAUnitTestClass.new
    obj.my_account = a
    assert_equal a, obj.my_account
    assert_equal 123, obj.image[ 'my_account' ]
  end

  def test_delegated_attr_accessor_assigns_object_without_reference_class
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs(internal_id: 123)

    TDAUnitTestClass.delegated_attr_accessor :my_account
    obj = TDAUnitTestClass.new
    assert_raises TypeError.new( "Can't save an object in my_account; did you forget to specify references_class?") do
      obj.my_account = a
    end
  end

  def test_delegated_attr_accessor_array
    TDAUnitTestClass.delegated_attr_accessor_array :my_list
    obj = TDAUnitTestClass.new
    obj.my_list = [ :xx, :xy, :xz ]
    assert_equal [ :xx, :xy, :xz ], obj.my_list
    obj.my_list = [ :x, :y, :z ]
    assert_equal [ :x, :y, :z ], obj.my_list
    obj.add_items_to_my_list [:a, :b]
    assert_equal [ :x, :y, :z, :a, :b ], obj.my_list
    obj.add_item_to_my_list :c
    assert_equal [ :x, :y, :z, :a, :b, :c ], obj.my_list
    obj.remove_item_from_my_list :b
    assert_equal [ :x, :y, :z, :a, :c ], obj.my_list
    obj.clear_my_list
    assert_equal [], obj.my_list
    obj.delete_my_list
    assert_false obj.image.has_key?( 'my_list')
  end

  def test_delegated_attr_accessor_array_with_key
    TDAUnitTestClass.delegated_attr_accessor_array :my_list, :hidden_element
    obj = TDAUnitTestClass.new
    obj.add_items_to_my_list [:a, :b]
    assert_equal [ :a, :b ], obj.my_list
    assert_equal [ :a, :b ], obj.image[ 'hidden_element']
    obj.add_item_to_my_list :c
    assert_equal [ :a, :b, :c ], obj.my_list
    obj.remove_item_from_my_list :b
    assert_equal [ :a, :c ], obj.my_list
    obj.clear_my_list
    assert_equal [], obj.my_list
    obj.delete_my_list
    assert_false obj.image.has_key?( 'my_list')
  end

  def test_delegated_attr_accessor_array_validates_each
    TDAUnitTestClass.delegated_attr_accessor_array :my_list, validates_each_with: :adds_one
    obj = TDAUnitTestClass.new
    obj.add_items_to_my_list [42, 43, 44]
    assert_equal [ 43, 44, 45 ], obj.my_list
  end

  def test_delegated_attr_accessor_array_after_change
    TDAUnitTestClass.delegated_attr_accessor_array :my_list, after_change: :set_flag
    obj = TDAUnitTestClass.new
    obj.add_item_to_my_list  42
    assert_equal [42], obj.my_list
    assert_true obj.flag
  end

  def test_delegated_attr_accessor_array_with_key_after_return
    TDAUnitTestClass.delegated_attr_accessor_array :my_list, :stored_as, after_return: :stringize_ary
    obj = TDAUnitTestClass.new
    obj.add_item_to_my_list  42
    assert_equal ["42"], obj.my_list
    assert_equal [42], obj.image[ 'stored_as' ]
    obj.delete_my_list
    assert_false obj.image.has_key?( 'stored_as' )
  end

  def test_delegated_attr_accessor_array_delegates_to
    TDAUnitTestClass.delegated_attr_accessor_array :my_list, delegates_to: :@alt_image
    obj = TDAUnitTestClass.new
    obj.add_item_to_my_list 42
    assert_equal [42], obj.my_list
    assert_equal [42], obj.alt_image[ 'my_list' ]
    assert_false obj.image.has_key?( 'my_list' )
  end

  def test_delegated_attr_accessor_array_references_class
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs(internal_id:123)
    b = Account.new
    b.stubs(internal_id:987)

    TDAUnitTestClass.delegated_attr_accessor_array :my_accounts, references_class: Account
    obj = TDAUnitTestClass.new
    Account.expects(:get).with(123).returns(a)
    Account.expects(:get).with(987).returns(b)
    obj.add_items_to_my_accounts [123,987]
    assert_equal [a,b], obj.my_accounts
    assert_equal [123,987], obj.image[ 'my_accounts' ]
  end

  def test_delegated_attr_accessor_array_references_class_assign_objects
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs( internal_id: 123 )
    b = Account.new
    b.stubs( internal_id: 987)

    TDAUnitTestClass.delegated_attr_accessor_array :my_accounts, references_class: Account
    obj = TDAUnitTestClass.new
    obj.add_items_to_my_accounts [a,b]
    assert_equal [a,b], obj.my_accounts
    assert_equal [123,987], obj.image[ 'my_accounts' ]
  end

  def test_delegated_attr_accessor_array_assigns_object_without_reference_class
    Object.const_set "Account", Class.new
    a = Account.new
    a.stubs( internal_id: 123 )
    b = Account.new
    b.stubs( internal_id: 987)

    TDAUnitTestClass.delegated_attr_accessor_array :my_accounts
    obj = TDAUnitTestClass.new
    assert_raises TypeError.new("Can't save an object in my_accounts; did you forget to specify references_class?") do
      obj.add_items_to_my_accounts [a,b]
    end
  end

  def test_delegated_attr_accessor_errors
    TDAUnitTestClass.delegated_attr_accessor_errors :mgmt_errors
    obj = TDAUnitTestClass.new
    obj.add_error_to_mgmt_errors( :approve_expenses, StandardError.new( "late again"))
    obj.add_error_to_mgmt_errors( :get_dressed, "ripped t-shirt")
    expected_mgmt_errors_approve_expenses_partial = {"class"=>"StandardError", "message"=>"late again", "trace"=>nil}
    expected_mgmt_errors_get_dressed_partial = {"message"=>"ripped t-shirt" }
    assert_equal [:approve_expenses, :get_dressed ], obj.mgmt_errors.keys
    assert_kind_of Time, obj.mgmt_errors[ :approve_expenses ].first.delete( 'timestamp')
    assert_kind_of Time, obj.mgmt_errors[ :get_dressed ].first.delete( 'timestamp')
    assert_equal expected_mgmt_errors_approve_expenses_partial, obj.mgmt_errors[ :approve_expenses ].first
    assert_equal expected_mgmt_errors_get_dressed_partial, obj.mgmt_errors[ :get_dressed ].first
  end

  def test_delegated_attr_accessor_errors_remove_clear
    TDAUnitTestClass.delegated_attr_accessor_errors :mgmt_errors
    obj = TDAUnitTestClass.new
    obj.add_error_to_mgmt_errors( :approve_expenses, StandardError.new( "late again"))
    obj.add_error_to_mgmt_errors( :get_dressed, "ripped t-shirt")
    obj.remove_action_from_mgmt_errors( :get_dressed )
    assert_equal [:approve_expenses ], obj.mgmt_errors.keys
    obj.clear_mgmt_errors
    assert_equal( {}, obj.mgmt_errors)
  end

end

