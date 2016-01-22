#!/bin/bash

# This starts up the services on first server, allowing the
# administrator to configure and start up a development or
# production system.

op=$1
bin_path=$2

case $op in
  start) 
    ${bin_path}/armagh-mongod start
    ${bin_path}/armagh-resource-admind start
    ${bin_path}/armagh-application-admind start
    ${bin_path}/armagh-agents-admind start
    ;;
  stop)
    ${bin_path}/armagh-agents-admind stop
    ${bin_path}/armagh-application-admind stop
    ${bin_path}/armagh-resource-admind stop
    ${bin_path}/armagh-mongod stop
    ;;
  restart)
    $0 stop
    $0 start
    ;;
  status)
    echo "ARMAGH DATABASE DAEMON STATUS:"
    ${bin_path}/armagh-mongod status
    echo -e "\n\nARMAGH RESOURCE ADMIN API DAEMON STATUS"
    ${bin_path}/armagh-resource-admind status
    echo -e "\n\nARMAGH APPLICATION ADMIN API DAEMON STATUS"
    ${bin_path}/armagh-application-admind status
    echo -e "\n\nARMAGH AGENT DAEMON STATUS"
    ${bin_path}/armagh-agentsd status
    ;;
  *)
    >&2 echo "usage: $0 [start|stop|restart|status]"
    ;;
esac
    
  
