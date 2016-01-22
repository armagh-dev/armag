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
    ;;
  stop)
    ${bin_path}/armagh-resource-admind stop
    ${bin_path}/armagh-mongod stop
    ;;
  restart)
    $0 stop
    $0 start
    ;;
  status)
    echo -e "\n*****************************\n"
    echo "ARMAGH DATABASE STATUS:"
    ${bin_path}/armagh-mongod status
    echo -e "\n\nARMAGH RESOURCE ADMIN API STATUS"
    ${bin_path}/armagh-resource-admind status
    echo -e "\n*****************************\n"
    ;;
  *)
    >&2 echo "usage: $0 [start|stop|restart|status]"
    ;;
esac
    
  
