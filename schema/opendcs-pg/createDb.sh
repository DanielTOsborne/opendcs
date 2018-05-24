#!/bin/bash

DH=%INSTALL_PATH

#
# Source the defines file
#
if [ ! -f defines.sh ]
then
  echo "There is no 'defines.sh' in the current directory."
  echo "CD to the opendcs-oracle schema directory before running this script."
  exit
fi
. defines.sh

# If you need a table space, define it here. then comment out the 
# non tablespace version of createdb below and uncomment the other one.
# TABLESPACE=pg_default

#cd %INSTALL_PATH%

echo -n "Enter db username of Open TSDB Administrator: "
read DBUSER
if [ -z "$DBUSER" ]
then
    echo "You must enter a database name for the TSDB administrator!"
	exit 1
fi
echo -n "Enter password for user $DBUSER:"
read -s PASSWD
echo
echo -n "Re-enter to verify:"
read -s PASSWD2
echo
if [ "$PASSWD" != "$PASSWD2" ]
then
	echo "Passwords do not match. Restart the script and try again."
	exit 1
fi

echo -n "Enter password for database super user $DBSUPER:"
read -s pw
echo
export PGPASSWORD="$pw"

echo -n "Enter number of numeric storage tables (default=10): "
read NUM_TABLES
if [ -z "$NUM_TABLES" ]
then
	NUM_TABLES=10
fi

echo -n "Enter number of string storage tables (default=5): "
read STRING_TABLES
if [ -z "$STRING_TABLES" ]
then
	STRING_TABLES=5
fi

echo "Will create $NUM_TABLES numeric tables and $STRING_TABLES string tables. (Press enter to continue)"
read x

echo "Defining Roles ..."
psql -q -U $DBSUPER -h $DBHOST -f group_roles.sql

echo "Creating database user $DBUSER ..."
createuser -U $DBSUPER -S -E -d -r -l -i -h $DBHOST $DBUSER
psql -q -U $DBSUPER -h $DBHOST -c "ALTER USER $DBUSER WITH PASSWORD '$PASSWD'"
psql -q -U $DBSUPER -h $DBHOST -c "GRANT \"OTSDB_ADMIN\" TO $DBUSER"

export PGPASSWORD="$PASSWD"
echo "Creating database as user $DBUSER (you will be prompted for password) ..."
# Non-tablespace:
createdb -U $DBUSER -h $DBHOST $DBNAME

# For tablespace, uncomment the following line and comment the above one:
# createdb -U $DBUSER -h $DBHOST -D $TABLESPACE $DBNAME

echo "Creating combined schema file ..."
echo '\set VERBOSITY terse' > combined.sql
cat opendcs.sql >> combined.sql
cat dcp_trans_expanded.sql >>combined.sql
./expandTs.sh $NUM_TABLES $STRING_TABLES
cat ts_tables_expanded.sql >>combined.sql
cat alarm.sql >>combined.sql
./makePerms.sh combined.sql
cat setPerms.sql >>combined.sql
cat sequences.sql >>combined.sql
echo "Setting Version Numbers ..."
echo >> combined.sql
echo "-- Set Version Numbers" >> combined.sql
echo 'delete from DecodesDatabaseVersion; ' >> combined.sql
echo "insert into DecodesDatabaseVersion values(15, '');" >> combined.sql
echo 'delete from tsdb_database_version; ' >> combined.sql
echo "insert into tsdb_database_version values(15, '');" >> combined.sql

for n in `seq 1 $NUM_TABLES`
do
	echo "insert into storage_table_list values($n, 'N', 0, 0);" >> combined.sql
done

for n in `seq 1 $STRING_TABLES`
do
	echo "insert into storage_table_list values($n, 'S', 0, 0);" >> combined.sql
done

echo "Creating schema as user $DBUSER (you will be prompted for password) ..."
psql -U $DBUSER -h $DBHOST -d $DBNAME -f combined.sql

echo "Importing Enumerations from edit-db ..."
$DH/bin/dbimport -l $LOG -r $DH/edit-db/enum/*.xml
echo "Importing Standard Engineering Units and Conversions from edit-db ..."
$DH/bin/dbimport -l $LOG -r $DH/edit-db/eu/EngineeringUnitList.xml
echo "Importing Standard Data Types from edit-db ..."
$DH/bin/dbimport -l $LOG -r $DH/edit-db/datatype/DataTypeEquivalenceList.xml
echo "Importing Presentation Groups ..."
$DH/bin/dbimport -l $LOG -r $DH/edit-db/presentation/*.xml
echo "Importing standard computation apps and algorithms ..."
$DH/bin/compimport -l $LOG $DH/imports/comp-standard/*.xml
echo "Importing DECODES loading apps ..."
$DH/bin/dbimport -l $LOG -r $DH/edit-db/loading-app/*.xml
