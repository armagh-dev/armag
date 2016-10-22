#!/bin/bash

# This starts up the services on first server, allowing the
# administrator to configure and start up a development or
# production system.

op=$1
bin_path=$2

if [[ ! -d ${ARMAGH_PID} ]]; then
  sudo mkdir -p ${ARMAGH_PID}
fi

case $op in
  start) 
    ${bin_path}/armagh-mongod start
    ${bin_path}/armagh-resource-admind start
    ${bin_path}/armagh-application-admind start
    ${bin_path}/armagh-agentsd start
    ;;
  stop)
    ${bin_path}/armagh-agentsd stop
    ${bin_path}/armagh-application-admind stop
    ${bin_path}/armagh-resource-admind stop
    ${bin_path}/armagh-mongod stop
    ;;
  restart)
    $0 stop
    $0 start
    ;;
  stat|status)
    echo -e "\n--------------------------------------------------------"
    echo -e "Armagh Process Status"
    ${bin_path}/armagh-mongod status
    ${bin_path}/armagh-resource-admind status
    ${bin_path}/armagh-application-admind status
    ${bin_path}/armagh-agentsd status
    echo -e "--------------------------------------------------------\n"
    ;;
  *)
    >&2 echo "usage: $0 [start|stop|restart|status]"
    ;;
esac
    
  
