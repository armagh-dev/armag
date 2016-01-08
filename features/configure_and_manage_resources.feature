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

Feature: Configure and manage resources
  In order to manage the resources supporting a scriptorium
  As an administrator
  I want to add, remove and monitor physical and logical resources
	
	# Note: Since the resources to be managed depend on the
	# design, and we don't have a design yet, this section
	# is intended as a guiding example only.
		
	Scenario: Adminstrator instantiates a scriptorium on one server.
	  Given the administrator has deployed scriptorium software on one server
		And administrative accounts have been created on the database on the server
		And the administrator has logged in
	  When the administrator opens a new scriptorium instantiation
		And the administrator enters a valid name for the scriptorium
		And the administrator accepts the defaults
		# whatever configurable params support each data store
		# whatever configurable params support how agents are spun up / shut down
		# other
		And the administrator submits the information
	  Then the system shall instantiate data stores
		And the system shall instantiate agent servers
	
	Scenario: Adminstrator initiates a scriptorium on three servers.
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator updates translation software on a one-server scriptorium clean.	
	  Given the adminstrator has instantiated a scriptorium on one server
		And the administrator has logged in
		When the administrator selects to update the translation software
		And the adminstrator uploads the translation software package
		And the administrator submits the information
	  Then the system shall verify that no existing subscriptions will be broken by loss of translation support
		And the system shall install the new translation software package on the server
		
	Scenario: Administrator views information on the installed translation software (version, translations available).
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator updates translation software on a three-server scriptorium.
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator attempts to update translation software that breaks subscriptions.
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator adds a server to expand processing capabilities
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator removes a server that does not support data stores.
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator backs up data stores and configurations
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator restores data stores and configurations
	  Given context
	  When event
	  Then outcome
	
	Scenario: Administrator attempts to reconfigure data store
	# to a different server, to a different partition, changes config params...
	  Given context
	  When event
	  Then outcome
	
	
	
	
  Scenario: Administrator updates translation software, supporting code for existing librarian agreement disappears.
	

	