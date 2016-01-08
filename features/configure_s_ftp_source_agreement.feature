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

Feature: Configure s/ftp source agreement
  In order to pull data from FTP-based sources
  As an administrator
  I want to be able to configure, test, and monitor FTP-based sources
	
	Scenario: Administrator opens a new S/FTP source to configure
	  Given the admin is logged in
	  When the admin starts a new S/FTP source agreement
		Then the method will default to "unsecured"
		Then the mode will default to "passive"
		And the port will default to "21"
		And the directory path will default to ""
		And the file pattern will default to "none"
		And the tracking method will default to "delete"
		And the archive directory will default to the configured archive directory
		And the status will default to "suspended"
		And the schedule will default to "hourly" at "00" after the hour
	
	Scenario: Adminstrator configures a basic S/FTP source
	  Given the admin is logged in
		And the admin opens a new S/FTP source to configure
		And the admin enters basic S/FTP source information
		  # the admin enters a valid unique name
		  # the admin enters a valid IP address
		  # the admin enters a valid username 
		  # the admin enters a valid password
			# the admin enters a valid technical contact name
			# the admin enters a valid technical contact email
			# the admin enters a valid technical contact phone
		And the admin submits the information
		Then the system shall save the new S/FTP source successfully
	    # the system shall validate connectivity by retrieving the source directory listing
		  # the system shall save the source agreement
		  # the system shall display a successful validation message
		  # the system shall display the source directory contents
	
  Scenario: Administrator configures an S/FTP source by hostname
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a valid hostname
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
  Scenario: Administrator configures an S/FTP source with active mode
	Scenario: Administrator configures an S/FTP source with secured method
	Scenario: Administrator configures an S/FTP source with secured method and new key pair
	Scenario: Administrator configures an S/FTP source with secured method and existing key pair
	Scenario: Administrator configures an S/FTP source with a non-standard port number
	Scenario: Administrator configures an S/FTP source with non-default directory path
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a valid directory path
		And the admin submits the information
    Then the system shall save the new FTP source successfully
		But shall display the source subdirectory contents
	
	Scenario: Administrator configures an S/FTP source with a specific file pattern
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a valid file pattern
		And the admin submits the information
    Then the system shall save the new FTP source successfully
		But the system shall only display the source directory content that matches the file pattern
  
	Scenario: Administrator configures an S/FTP source with a valid custom archive path
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a valid custom archive path
		And the admin submits the information
    Then the system shall save the new FTP source successfully
  
	Scenario: Administrator configures an S/FTP source with a custom hourly schedule
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a schedule of "hourly" at "33" after the hour
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
	Scenario: Administrator configures an S/FTP source with a daily schedule
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a schedule of "daily" at "13:00"
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
	Scenario: Administrator configures an S/FTP source with hash tracking
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a tracking method of "hash"
		And the admin submits the information
    Then the system shall save the new FTP source successfully
  
	Scenario: Administrator configures an S/FTP source with title tracking
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a tracking method of "title"
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
  Scenario: Administrator configures an S/FTP source with IPv6 IP address
	Scenario: Administrator tests an existing S/FTP source
	
	Scenario: Administrator misconfigures an S/FTP source with an empty name
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a name of ""
		And the admin submits the information
    Then the system shall reject the FTP source
		And the system shall display an empty name error
	
	Scenario: Administrator misconfigures an S/FTP source with a non-unique name
    Given the admin logged in
		And there is a source agreement named "fred"
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		And the admin enters a name of "fred"
		And the admin submits the information
    Then the system shall reject the FTP source
		And the system shall display a non-unique name error
	
  Scenario: Administrator misconfigures an S/FTP source with an empty IP address
	Scenario: Administrator misconfigures an S/FTP source with a malformed IP address
	Scenario: Administrator misconfigures an S/FTP source with a malformed port number
  Scenario: Administrator configures an S/FTP source with host that cannot be reached
  Scenario: Administrator misconfigures an S/FTP source with an empty username
	Scenario: Administrator misconfigures an S/FTP source with an empty password
	Scenario: Administrator misconfigures an S/FTP source with invalid user credentials
  Scenario: Administrator misconfigures an S/FTP source with malformed file pattern
  Scenario: Administrator misconfigures an S/FTP source with schedule missing cron parameter
  Scenario: Administrator misconfigures an S/FTP source with hourly schedule with invalid hour
  Scenario: Administrator misconfigures an S/FTP source with daily schedule with invalid time
  Scenario: Administrator misconfigures an S/FTP source with weekly schedule with invalid time
  Scenario: Administrator misconfigures an S/FTP source with weekly schedule with invalid day-of-week
	Scenario: Administrator misconfigures an S/FTP source with non-existent directory path
	Scenario: Administrator misconfigures an S/FTP source with unauthorized directory path
	Scenario: Administrator misconfigures an S/FTP source with non-existent archive path
	Scenario: Administrator misconfigures an S/FTP source with unauthorized archive path
	Scenario: Administrator misconfigures an S/FTP source with an empty technical contact name
	Scenario: Administrator misconfigures an S/FTP source with an empty technical contact email
	Scenario: Administrator misconfigures an S/FTP source with an empty technical contact phone
	
	Scenario: Administrator views chart of documents collected vs time
	Scenario: Administrator views collection error log
	
	
