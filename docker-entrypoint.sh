#!/bin/bash
if [[ $DEBUG == "true" ]]; then
  set -x
fi
set -e

ts=$(date '+%F %T');
echo "$ts Entering entrypoint"

# SIGTERM-handler
_term() {
  echo "Caught SIGTERM signal!"
  pid=$(pgrep -f CodeServerMain)
  mzsh shutdown platform

  # Wait for graceful termination
  timeout=300
  counter=0
  force_shutdown=false

  while ps -p "$pid" > /dev/null; do
    if [[ ! $counter < $timeout ]]; then
      # timeout reached
      if [[ $force_shutdown == true ]]; then
        echo "Shutdown failed. Exiting..."
        exit 1
      fi
      echo "Graceful shutdown timeout reached. Trying kill instead..."
      kill -TERM "$pid"
      force_shutdown=true
      # reset counter
      counter=0
    fi
    sleep 1;
    ((counter++))
  done
}

exit_script() {
    echo "=================== Printing something special! ==================="
    echo "=================== Maybe executing other commands! ==================="
    trap - SIGINT SIGTERM # clear the trap
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

trap exit_script SIGINT SIGTERM

cp /etc/config/common/* $MZ_HOME/etc

while getopts j:e: opts; do
  case "${opts}" in
    e)
      ESCAPED_ARG=$(echo "$OPTARG" | sed 's/\$/\\\$/g; s/[[:space:]]/\\ /2g')
      OPTS="$OPTS -e $ESCAPED_ARG"
      ;;
    j)
      OPTS="$OPTS -j $OPTARG"
      ;;
   esac
done

MZ_JDBC_PASSWORD=$(echo $MZ_JDBC_PASSWORD|base64)

OPTS="$OPTS -e mz.jdbc.user=$MZ_JDBC_USER -e mz.jdbc.password=$MZ_JDBC_PASSWORD"

if [[ $TLS_ENABLED == "true" ]]; then

  TLS_KEYSTORE_PASSWORD=$(echo $TLS_KEYSTORE_PASSWORD|base64)
  TLS_KEY_PASSWORD=$(echo $TLS_KEY_PASSWORD|base64)

	OPTS="$OPTS -e mz.httpd.security=$TLS_ENABLED -e mz.httpd.security.keystore=$TLS_KEYSTORE -e mz.httpd.security.keystore.password=$TLS_KEYSTORE_PASSWORD -e mz.httpd.security.key.alias=$TLS_KEY_ALIAS -e mz.httpd.security.key.password=$TLS_KEY_PASSWORD -e pico.rcp.tls.keystore=$TLS_KEYSTORE -e pico.rcp.tls.keystore.password=$TLS_KEYSTORE_PASSWORD -e pico.rcp.tls.key.password=$TLS_KEY_PASSWORD"
fi
if [[ ! -z "$OPERATOR_PASSWORD" ]]; then
	OPTS="$OPTS -e mz.operator.password=$OPERATOR_PASSWORD"
fi

$MZ_HOME/entrypoint/generate-license-file.sh

# this ensures that the mzsh log file appears in the correct location
export MZSH_PICO_TYPE="platform"

ts=$(date '+%F %T');
echo "$ts Getting startup cmd..."
start_pico=$(eval "mzsh startup platform $OPTS -v show-cmdline-and-exit")
ts=$(date '+%F %T');
echo "$ts Done getting startup cmd"

ts=$(date '+%F %T');
if [[ $DEBUG == "true" ]]; then
	echo "$ts Starting platform with cmd: " $start_pico
else
	echo "$ts Starting platform"
fi

tail -F persistent/log/platform/platform_current.log&

eval $start_pico &

child=$!

echo "================================ TEST HERE ================================"

wait "$child"

