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
require_relative '../helpers/coverage_helper'
require_relative '../helpers/integration_helper'

require_relative '../../lib/armagh/environment'
Armagh::Environment.init

require_relative '../helpers/mongo_support'
require_relative '../../lib/armagh/connection'

require_relative '../../lib/armagh/document/base_document/document'
require_relative '../../lib/armagh/document/base_document/locking_crud'
require_relative '../../lib/armagh/connection/mongo_error_handler'
require 'test/unit'
require 'mocha/test_unit'


class TIBDSimplePerson < Armagh::BaseDocument::Document
  def self.default_collection; Armagh::Connection::MongoConnection.instance.connection['doc_a']; end
  delegated_attr_accessor :name
  delegated_attr_accessor :message
end

class TIBDLockingPerson < Armagh::BaseDocument::Document
  include Armagh::BaseDocument::LockingCRUD
  def self.default_collection; Armagh::Connection::MongoConnection.instance.connection['lock_doc_a']; end
  def self.default_lock_hold_duration; 10; end
  def self.default_lock_wait_duration; 15; end
  delegated_attr_accessor :name
  delegated_attr_accessor :role, :rl_cd
  delegated_attr_accessor :message, validates_with: :dont_shout
  delegated_attr_accessor :best_friend, references_class: TIBDSimplePerson
  delegated_attr_accessor_array :other_friends, references_class: TIBDSimplePerson
  delegated_attr_accessor_array :team, references_class: TIBDSimplePerson
  delegated_attr_accessor_errors :my_mistakes

  def dont_shout( str )
    str.downcase
  end

end


class TestIntegrationBaseDocument < Test::Unit::TestCase

  def setup
    @collection = Armagh::Connection::MongoConnection.instance.connection['test_collection']
    @agent1 = mock
    @agent1.stubs( signature: 'agent1', running?: true )
    @agent2 = mock
    @agent2.stubs( signature: 'agent2', running?: true )
  end

  def teardown
    MongoSupport.instance.clean_database
  end

  def test_create
    name = 'Emmet'
    message = 'Everything is awesome'
    t = Time.now
    person_doc = TIBDSimplePerson.create_one( {'name' => name, 'message' => message})
    pdoc = TIBDSimplePerson.get person_doc.internal_id
    assert_equal name, pdoc.name
    assert_equal message, pdoc.message
    assert_in_delta t, pdoc.created_timestamp, 2
    assert_equal pdoc.created_timestamp, pdoc.updated_timestamp
  end

  def test_create_locked
    name = 'Emmet'
    message = 'Everything is awesome'
    t = Time.now
    person_doc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message}, @agent1)
    pdoc = TIBDLockingPerson.get_read_only person_doc.internal_id
    assert_equal name, pdoc.name
    assert_equal message.downcase, pdoc.message
    assert_in_delta t, pdoc.created_timestamp, 2
    assert_equal pdoc.created_timestamp, pdoc.updated_timestamp
    assert_true pdoc.locked_by_anyone?
    assert_equal @agent1.signature, pdoc.locked_by
    sleep TIBDLockingPerson.default_lock_hold_duration
    assert_false pdoc.locked_by_anyone?
    assert_nil pdoc.locked_by
  end

  def test_create_locked_find_collision
    name = 'Emmet'
    message = 'Everything is awesome'
    t = Time.now
    person_doc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message}, @agent1)
    pdoc = TIBDLockingPerson.get_read_only person_doc.internal_id
    assert_equal name, pdoc.name
    assert_equal message.downcase, pdoc.message
    assert_in_delta t, pdoc.created_timestamp, 2
    assert_equal pdoc.created_timestamp, pdoc.updated_timestamp
    assert_true pdoc.locked_by_anyone?
    assert_equal @agent1.signature, pdoc.locked_by

    assert_raises( Armagh::BaseDocument::LockTimeoutError ) do
      TIBDLockingPerson.get_locked person_doc.internal_id, @agent2, lock_wait_duration: 1
    end

    sleep TIBDLockingPerson.default_lock_hold_duration
    assert_false pdoc.locked_by_anyone?
    assert_nil pdoc.locked_by
  end

  def test_create_locked_find_collision_resolves
    name = 'Emmet'
    message = 'Everything is awesome'
    t = Time.now
    person_doc = TIBDLockingPerson.create_one_unlocked( {'name' => name, 'message' => message} )

    t = Thread.new {
      TIBDLockingPerson.with_new_or_existing_locked_document( { '_id': person_doc.internal_id }, {}, @agent1, lock_hold_duration: 10 ) do |d|
      end
    }

    agent2s_pdoc = TIBDLockingPerson.get_locked person_doc.internal_id, @agent2, lock_wait_duration: 20

    assert_true agent2s_pdoc.locked_by_anyone?
    assert_equal @agent2.signature, agent2s_pdoc.locked_by

  end

  def test_create_locked_save_extending_lock
    name = 'Emmet'
    message = 'Everything is awesome'
    t = Time.now
    agent1s_pdoc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message}, @agent1)

    assert_equal name, agent1s_pdoc.name
    assert_equal message.downcase, agent1s_pdoc.message
    assert_in_delta t, agent1s_pdoc.created_timestamp, 2
    assert_equal agent1s_pdoc.created_timestamp, agent1s_pdoc.updated_timestamp
    assert_true agent1s_pdoc.locked_by_anyone?
    assert_equal @agent1.signature, agent1s_pdoc.locked_by

    locked_until_before_save = agent1s_pdoc.locked_by_me_until( @agent1 )
    agent1s_pdoc.message = "Everything is cool when you're part of a team."
    sleep 1
    agent1s_pdoc.save( false, @agent1 )
    locked_until_after_save = agent1s_pdoc.locked_by_me_until( @agent1 )
    assert_not_equal locked_until_before_save.to_f, locked_until_after_save.to_f
  end

  def test_change_collection_save
    name = 'Emmet'
    message = 'Everything is awesome'
    pdoc = TIBDSimplePerson.create_one( {'name' => name, 'message' => message})

    assert_equal 1, TIBDSimplePerson.default_collection.count
    assert_equal 0, @collection.count

    pdoc.save( in_collection: @collection )

    assert_equal 0, TIBDSimplePerson.default_collection.count
    assert_equal 1, @collection.count
  end

  def test_change_collection_save_locked_to_unlocked
    name = 'Emmet'
    message = 'Everything is awesome'
    a1s_pdoc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message}, @agent1)

    assert_equal 1, TIBDLockingPerson.default_collection.count
    assert_equal 0, @collection.count

    a1s_pdoc.save( true, @agent1, in_collection: @collection )

    assert_equal 0, TIBDLockingPerson.default_collection.count
    assert_equal 1, @collection.count
  end

  def test_delete
    name = 'Emmet'
    message = 'Everything is awesome'
    a1s_pdoc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message}, @agent1)
    a1s_pdoc.delete( @agent1 )

    assert_equal 0, TIBDLockingPerson.default_collection.count
  end

  def test_delete_you_cant_delete_that
    name = 'Emmet'
    message = 'Everything is awesome'
    a1s_pdoc = TIBDLockingPerson.create_one_locked( {'name' => name, 'message' => message, 'document_id' => 'docid'}, @agent1)

    e = assert_raises( Armagh::Connection::ConnectionError) do
      a1s_pdoc.delete( @agent2 )
    end
    assert_match /Unable to delete TIBDLockingPerson docid from lock_doc_a/, e.message
  end

  def test_lots_of_attributes_and_update

    name = "Emmet"
    message = "Everything is Awesome!"
    role = "85_builder"
    wyldstyle = TIBDSimplePerson.create_one( { name: 'Wyldstyle', message: 'that was literally the dumbest thing i have ever heard' })
    bad_cop = TIBDSimplePerson.create_one( { name: 'bad cop', message: 'darn darn darn darny-darn'})
    batman = TIBDSimplePerson.create_one( { name: 'batman', message: 'I only work in black and sometimes very, very dark grey.'})
    vitruvius = TIBDSimplePerson.create_one( { name: 'vitruvius', message: 'The prophecy... I made it up.'})
    emmet = TIBDLockingPerson.create_one_locked( {
      name: name,
      message: message,
      role: role,
      best_friend: wyldstyle
    }, @agent1)

    assert_equal name, emmet.name
    assert_equal message.downcase, emmet.message
    assert_equal role, emmet.role
    assert_equal role, emmet.to_hash[ 'rl_cd']

    emmet.add_items_to_other_friends [ batman, bad_cop, vitruvius ]
    emmet.remove_item_from_other_friends bad_cop
    assert_equal wyldstyle, emmet.best_friend
    assert_equal wyldstyle.internal_id, emmet.to_hash[ 'best_friend' ]
    assert_equal [ batman, vitruvius ], emmet.other_friends
    assert_equal [ batman.internal_id, vitruvius.internal_id ], emmet.to_hash[ 'other_friends' ]

    emmet.save( false, @agent1 )
  end

end

