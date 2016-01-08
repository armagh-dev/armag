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

Feature: Manage administrators
  In order to secure the scriptorium
  As an administrator
  I want to manage administrator accounts
			
	Scenario: Administrator logs in
	  Given the administrator has deployed scriptorium software
		And the adminstrator is not logged in
	  When the administrator enters valid credentials
		And the administrator submits the information
	  Then the administrator will have access to administrative functions.
	
	Scenario: Administrator changes own password
	  Given the administrator has logged in
	  When the administrator chooses to change its password
		And the administrator enters a valid new password
		And the administrator submits the information
	  Then the administrator's credentials will be changed
	
	Scenario: Administrator changes another's password
	  Given the administrator has logged in
	  When the administrator chooses to change another administrator's password
		And the administrator enters a valid new password
		And the administrator submits the information
	  Then the other administrator's credentials will be changed
	
	Scenario: Administrator creates a new administrator account
	  Given the administrator has logged in
	  When the administrator chooses to create a new administrator account
		And the administrator enters a valid user name
		And the administrator enters a valid password
		And the administrator submits the information
	  Then the new administrator account shall be created
	
	Scenario: Administrator deletes another administrator account
	  Given the administrator has logged in
	  When the administrator chooses to delete another administrator's account
	  Then the other administrator's account shall be deleted
	
	Scenario: Administrator attempts to delete own account
	  Given the administrator has logged in
	  When the administrator attempts to delete its own account
	  Then the operation will be disabled or fail
	
