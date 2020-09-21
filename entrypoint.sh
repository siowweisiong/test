#!/usr/bin/env bash

# SIGTERM-handler
_term() {
  echo "Caught SIGTERM signal!"
  pid=$(jps|grep PicoStart|awk '{print $1}')
  kill -TERM "$pid"
  # Wait for graceful termination
  while ps -p $pid > /dev/null; do sleep 1; done;
}

trap _term SIGTERM

if [ "$(ls -1 /etc/config/common/ | wc -l)" -ne 1 ]; then
  echo "One config file is required in /etc/config/common/"
  lsresult="$(ls -l /etc/config/common/)"
  echo "Current contents: " $lsresult
  exit
else
  cp /etc/config/common/* $MZ_HOME/common/config/cell/default/.active/cell.conf
fi

if [ "$(ls -1 /etc/config/container/ 2>/dev/null | wc -l)" -gt 1 ]; then
  echo "Maximum one config file is allowed in /etc/config/container/"
  lsresult="$(ls -l /etc/config/container/)"
  echo "Current contents: " $lsresult
  exit
else
  cp /etc/config/container/* $MZ_HOME/common/config/cell/default/.active/containers/$MZ_CONTAINER/container.conf 2>/dev/null
fi

if [ "$(ls -1 /etc/config/pico/ | wc -l)" -ne 1 ]; then
  echo "One config file is required in /etc/config/pico/"
  lsresult="$(ls -l /etc/config/pico/)"
  echo "Current contents: " $lsresult
  exit
else
  cp /etc/config/pico/* $MZ_HOME/common/config/cell/default/.active/containers/$MZ_CONTAINER/picos/$(hostname).conf
fi

sed -i '6s/args/debug/; 7s/.*/          "-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=5006"/' $MZ_HOME/common/config/cell/default/.active/containers/$MZ_CONTAINER/picos/$(hostname).conf

start_pico="$(mzsh startup $(hostname) -v show-cmdline-and-exit)"
echo "About to start $(hostname) with " $start_pico
eval $start_pico &

child=$!
echo "Waiting for child $child"

wait "$child"



