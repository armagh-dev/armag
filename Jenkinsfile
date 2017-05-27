#!groovy

import hudson.Util;

try {

currentBuild.result = "SUCCESS"


  node('armagh-builder') {

     stage('Prep') {

       deleteDir()
     
       checkout scm

       sh """#!/bin/bash -l
         echo -e "*********************************************\n** Preparing:" `hg identify -i` "\n*********************************************"
         set -e
         gem install bundler --no-doc
         bundle install
         ruby --version
         mongod --version
       """
     }
  
     stage('Unit Test') {
     
       sh """#!/bin/bash -l
         echo -e "*********************************************\n** Unit testing:" `hg identify -i` "\n*********************************************"
         set -e
         bundle exec rake test
       """
     }
  
     stage('Integration Test') {
     
       sh """#!/bin/bash -l
         echo -e "*********************************************\n** Integration testing:" `hg identify -i` "\n*********************************************"
         set -e
         bundle exec rake integration
       """
     }

     stage('Cucumber Test') {
     
       sh """#!/bin/bash -l
         echo -e "*********************************************\n** Cucumber testing:" `hg identify -i` "\n*********************************************"
         set -e
         bundle exec rake cucumber
       """
     }

     stage('Rcov') {
     
       publishHTML (target: [
         allowMissing: false,
         alwaysLinkToLastBuild: false,
         keepAll: true,
         reportDir: 'coverage/rcov',
         reportFiles: 'index.html',
         reportName: "RCov Report"
       ])
     }

     stage('Yard') {

       sh """#!/bin/bash -l
         echo -e "*********************************************\n** Yard:" `hg identify -i` "\n*********************************************"
         set -e
         bundle exec rake yard
       """
     
       publishHTML (target: [
         allowMissing: false,
         alwaysLinkToLastBuild: false,
         keepAll: true,
         reportDir: 'doc',
         reportFiles: 'index.html',
         reportName: "YARD Documentation"
       ])
     }
  }
}

catch( err ) {
  currentBuild.result = "FAILURE! - ${err}"
  throw err
}

finally {

  println "********************\n** EXECUTING FINALLY BLOCK \n********************\n"

  def buildDuration = Util.getTimeSpanString(System.currentTimeMillis() - currentBuild.startTimeInMillis)

  slackSend message: "${env.JOB_NAME} - #${env.BUILD_NUMBER} ${currentBuild.result} after ${buildDuration} (<${env.BUILD_URL}|Open>)"

  // Remove older build
  properties([[$class: 'BuildDiscarderProperty', strategy: [$class: 'LogRotator', artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '', numToKeepStr: '10']]]);

}
