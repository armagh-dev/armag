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

Feature: Deploy core software
  In order to prepare an environment to provide scriptorium services
  As an administrator
  I want to deploy scriptorium software
		
	Scenario: Administrator deploys scriptorium software on one server.
	  Given no scriptoria exist on the server
	  When the administrator installs the scriptorium software on the server
	  Then the installer will prompt the administrator to define admin logins and passwords on the server
		And the installer shall deploy the software on the server
		And the installer shall start any database servers on the server, including creation of administration accounts
		And the installer shall start any agent servers on the server, including creation of administration accounts
	
	Scenario: Administrator deploys scriptorium software on three servers.
	  Given no scriptoria exist on each server
	  When the administrator installs the scriptorium software on each server
	  Then the installer will prompt the administrator to define admin logins and passwords on each server
		And the installer shall deploy the software on each server
		And the installer shall start any database servers on each server, including creation of administration accounts
		And the installer shall start any agent servers on each server, including creation of administration accounts
	
	Scenario: Administrator updates scriptorium software (clean)
	Scenario: Administrator updates scriptorium software (data migration - need solid examples)
	