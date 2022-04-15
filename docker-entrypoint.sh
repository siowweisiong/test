#!/bin/bash

#if [[ $DEBUG == "true" ]]; then
#  set -x
#fi
#set -e

#ts=$(date '+%F %T');
#echo "$ts Entering entrypoint"

# SIGTERM-handler
_term() {
  echo "Caught SIGTERM signal!"
  echo "Caught SIGTERM signal!" >> persistent/log/platform/platform_current.log

  pid=$(pgrep -f CodeServerMain)
  kill -TERM "$pid"
  # Wait for graceful termination
  while ps -p $pid > /dev/null; do sleep 1; done;
}

trap _term SIGTERM

####################### REPLACE #######################

#Initialize counter variable, i
i=1

#declare infinite for loop
while true;
do
  echo “running the loop for $i times” >> persistent/log/platform/platform_current.log
  ((i++))
  sleep 1;
done

