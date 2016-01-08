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

Feature: Configure http/s source agreement
  In order to pull data from HTTP-based sources
  As an administrator
  I want to be able to configure, test, and monitor HTTP-based sources
	
	Scenario: Administrator opens a new HTTP/S source to configure
	  Given the admin is logged in
	  When the admin starts a new HTTP/S source agreement
		Then the authentication method will default to "none"
		And the port will default to "80"
		And the tracking method will default to "body"
		And the archive directory will default to the configured archive directory
		And the status will default to "suspended"
		And the schedule will default to "hourly" at "00" after the hour
	
	Scenario: Adminstrator configures a basic HTTP/S source
	  Given the admin is logged in
		And the admin opens a new HTTP/S source to configure
		And the admin enters basic HTTP/S source information
		  # the admin enters a valid unique name
		  # the admin enters a valid URL
			# the admin enters a valid technical contact name
			# the admin enters a valid technical contact email
			# the admin enters a valid technical contact phone
		And the admin submits the information
		Then the system shall save the new HTTP/S source successfully
	    # the system shall validate connectivity by retrieving the page
		  # the system shall save the source agreement
		  # the system shall display a successful validation message
		  # the system shall display the retrieved page
	
	Scenario: Administrator configures an HTTP/S source with basic authentication
	Scenario: Administrator configures an HTTP/S source with key-based authentication and new key pair
	Scenario: Administrator configures an HTTP/S source with key-based authentication and existing key pair
	Scenario: Administrator configures an HTTP/S source with a non-standard port number
	Scenario: Administrator configures an HTTP/S source with query parameters
	Scenario: Administrator configures an HTTP/S source with form parameters
	Scenario: Administrator configures an HTTP/S source with a valid custom archive path
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a valid custom archive path
		And the admin submits the information
    Then the system shall save the new FTP source successfully
  
	Scenario: Administrator configures an HTTP/S source with a custom hourly schedule
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a schedule of "hourly" at "33" after the hour
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
	Scenario: Administrator configures an HTTP/S source with a daily schedule
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a schedule of "daily" at "13:00"
		And the admin submits the information
    Then the system shall save the new FTP source successfully
	
	Scenario: Administrator tests an existing HTTP/S source
	
	Scenario: Administrator misconfigures an HTTP/S source with an empty name
    Given the admin logged in
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		But the admin enters a name of ""
		And the admin submits the information
    Then the system shall reject the FTP source
		And the system shall display an empty name error
	
	Scenario: Administrator misconfigures an HTTP/S source with a non-unique name
    Given the admin logged in
		And there is a source agreement named "fred"
		When the admin opens a new FTP source to configure
		And the admin enters basic FTP source information
		And the admin enters a name of "fred"
		And the admin submits the information
    Then the system shall reject the FTP source
		And the system shall display a non-unique name error
	
	Scenario: Administrator misconfigures an HTTP/S source with an empty URL
	Scenario: Administrator misconfigures an HTTP/S source with a malformed URL
  Scenario: Administrator configures an HTTP/S source with host that cannot be reached
  Scenario: Administrator misconfigures an HTTP/S source with basic authentication and an empty username
	Scenario: Administrator misconfigures an HTTP/S source with basic authentication and an empty password
	Scenario: Administrator misconfigures an HTTP/S source with basic authentication and invalid user credentials
	Scenario: Administrator misconfigures an HTTP/S source with key authentication and a deleted key file
	Scenario: Administrator misconfigures an HTTP/S source with key authentication and an invalid key
  Scenario: Administrator misconfigures an HTTP/S source with malformed form parameters
  Scenario: Administrator misconfigures an HTTP/S source with schedule missing cron parameter
  Scenario: Administrator misconfigures an HTTP/S source with hourly schedule with invalid hour
  Scenario: Administrator misconfigures an HTTP/S source with daily schedule with invalid time
  Scenario: Administrator misconfigures an HTTP/S source with weekly schedule with invalid time
  Scenario: Administrator misconfigures an HTTP/S source with weekly schedule with invalid day-of-week
	Scenario: Administrator misconfigures an HTTP/S source with non-existent directory path
	Scenario: Administrator misconfigures an HTTP/S source with unauthorized directory path
	Scenario: Administrator misconfigures an HTTP/S source with non-existent archive path
	Scenario: Administrator misconfigures an HTTP/S source with unauthorized archive path
	Scenario: Administrator misconfigures an HTTP/S source with an empty technical contact name
	Scenario: Administrator misconfigures an HTTP/S source with an empty technical contact email
	Scenario: Administrator misconfigures an HTTP/S source with an empty technical contact phone
	
	Scenario: Administrator views chart of documents collected vs time
	Scenario: Administrator views collection error log
	
	
