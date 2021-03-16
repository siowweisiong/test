#!/bin/bash

if [[ $DEBUG == "true" ]]; then
  set -x
fi
set -e

export MZ_JDBC_PASSWORD=$1

PERSISTENT_DIR=$MZ_HOME/persistent
BACKUP_DIR=$PERSISTENT_DIR/backup

echo "Installing oracle sqlplus"
sudo alien -i /opt/mz/persistent/3pp/oracle-instantclient19.9-basiclite-19.9.0.0.0-1.x86_64.rpm
sudo alien -i /opt/mz/persistent/3pp/oracle-instantclient19.9-sqlplus-19.9.0.0.0-1.x86_64.rpm
echo "/usr/lib/oracle/19.9/client64/lib" | sudo tee -a /etc/ld.so.conf.d/oracle.conf
sudo ldconfig
LOCAL_ORACLE_HOME="/usr/lib/oracle/19.9/client64"
SQLPLUS_PATH="$LOCAL_ORACLE_HOME/bin/sqlplus"
echo "Successfully installed oracle sqlplus"

SQLPLUS_DBA="$SQLPLUS_PATH -l -s $ORACLE_ADMIN_USER/$ORACLE_ADMIN_PASSWORD@//$ORACLE_HOST:$ORACLE_PORT AS SYSDBA"
SQLPLUS_MZ_DBA="$SQLPLUS_PATH -l -s $ORACLE_ADMIN_USER/$ORACLE_ADMIN_PASSWORD@//$ORACLE_HOST:$ORACLE_PORT/$ORACLE_DATABASE AS SYSDBA"
SQLPLUS_MZ="$SQLPLUS_PATH -l -s $MZ_JDBC_USER/$MZ_JDBC_PASSWORD@//$ORACLE_HOST:$ORACLE_PORT/$ORACLE_DATABASE"

echo "Checking database..."
($SQLPLUS_MZ <<-EOF) && true
  whenever oserror exit 42;
  whenever sqlerror exit sql.sqlcode;
  -- this is a query that will not be successful unless the db is setup and the mz tables have been loaded
  SELECT COUNT(username) FROM mz_user;
EOF
RETURN_CODE=$?
echo "Return code: $RETURN_CODE"
if [[ RETURN_CODE -eq 0 ]]
then
  echo "Database is already setup"
  exit 0
else
  echo "New installation detected"
	if [[ -f $BACKUP_DIR/mz.version ]]
	then
    rm -rf $BACKUP_DIR/mz.version
  fi
fi

if [[ -z "$ORACLE_ADMIN_USER" || -z "$ORACLE_ADMIN_PASSWORD" ]]; then
  echo "Not allowed to setup oracle automatically"
	if [[ -f $BACKUP_DIR/mz.version ]]
	then
    rm -rf $BACKUP_DIR/mz.version
  fi
  echo "Creating database setup scripts"
  $MZ_HOME/sql/oracle/dbscript_setup.sh $ORACLE_DB_SIZE $ORACLE_DATABASE $ORACLE_DATA
	TAR_FILE=database-setup.tar
  EXPORT_NAME=$BACKUP_DIR/$TAR_FILE
	tar cfz $EXPORT_NAME -C /tmp/oracle_setup .
	echo "Tar file $EXPORT_NAME contains the scripts for manual database setup"
	exit 1
fi

# Oracle XE automatic database setup
if [[ $ORACLE_XE = true ]]
then
  # For Oracle XE automatic setup we use the local oracle home
  export ORACLE_HOME=$LOCAL_ORACLE_HOME

  echo "Creating database setup scripts"
  $MZ_HOME/sql/oracle/dbscript_setup.sh $ORACLE_DB_SIZE $ORACLE_DATABASE $ORACLE_DATA

  cd /tmp/oracle_setup

  ($SQLPLUS_DBA < oracle_xe_create_db.sql) && true
  RETURN_CODE=$?
  echo "Return code: $RETURN_CODE"
  if [[ $RETURN_CODE -eq 244 ]]
  then
    echo "Database already exists"
  elif [[ $RETURN_CODE -eq 0 ]]
  then
    echo "Database created"
  else
    echo "Failed to create database"
    exit 1
  fi

  ($SQLPLUS_MZ_DBA < oracle_create_ts.sql) && true
  RETURN_CODE=$?
  echo "Return code: $RETURN_CODE"
  if [[ $RETURN_CODE -eq 7 ]]
  then
    echo "Tablespace already created"
  elif [[ $RETURN_CODE -eq 0 ]]
  then
    echo "Tablespace created"
  else
    echo "Failed to create tablespace"
  fi

  ($SQLPLUS_MZ_DBA < oracle_user.sql) && true
  RETURN_CODE=$?
  echo "Return code: $RETURN_CODE"

  # login in as the newly created mz jdbc user and execute a query as a sanity check that the db is ok
  ($SQLPLUS_MZ <<-EOF) && true
    whenever oserror exit 42;
    whenever sqlerror exit sql.sqlcode;
    SELECT * FROM ALL_USERS ORDER BY CREATED;
EOF
  RETURN_CODE=$?
  echo "Return code: $RETURN_CODE"
  if [[ RETURN_CODE -eq 0 ]]
  then
    echo "Database is successfully setup"
    exit 0
  else
    echo "Database setup failed"
    exit 1
  fi
else
  echo "Automatic database setup is only supported for Oracle XE"
  exit 1
fi

