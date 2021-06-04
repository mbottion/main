
#
#   This scipt exports the BNA schema for further usage (OAC)
#


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
die() 
{
  echo "
ERROR :
  $*"
  exit 1
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
exec_sql()
{
#
#  Don't forget to use : set -o pipefail un the main program to have error managempent
#
  local VERBOSE=N
  local SILENT=N
  if [ "$1" = "-silent" ]
  then 
    SILENT=Y
    shift
  fi
  if [ "$1" = "-no_error" ]
  then
    err_mgmt="whenever sqlerror continue"
    shift
  else
    err_mgmt="whenever sqlerror exit failure"
  fi
  if [ "$1" = "-verbose" ]
  then
    VERBOSE=Y
    shift
  fi
  local login="$1"
  local stmt="$2"
  local lib="$3"
  local bloc_sql="$err_mgmt
set recsep off
set head off 
set feed off
set pages 0
set lines 2000
connect ${login}
$stmt"
  REDIR_FILE=""
  REDIR_FILE=$(mktemp)
  if [ "$lib" != "" ] 
  then
     printf "%-75s : " "$lib";
     sqlplus -s /nolog >$REDIR_FILE 2>&1 <<%EOF%
$bloc_sql
%EOF%
    status=$?
  else
     sqlplus -s /nolog <<%EOF% | tee $REDIR_FILE  
$bloc_sql
%EOF%
    status=$?
  fi
  if [ $status -eq 0 -a "$(egrep "SP2-" $REDIR_FILE)" != "" ]
  then
    status=1
  fi
  if [ "$lib" != "" ]
  then
    [ $status -ne 0 ] && { echo "*** ERREUR ***" ; test -f $REDIR_FILE && cat $REDIR_FILE ; rm -f $REDIR_FILE ; } \
                      || { echo "OK" ; [ "$VERBOSE" = "Y" ] && test -f $REDIR_FILE && cat $REDIR_FILE ; }
  fi 
  rm -f $REDIR_FILE
  [ $status -ne 0 ] && return 1
  return $status
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

testPDB()
{
  printf "%-75s : " "  - Testing that PDB is $1"
  ret=$(exec_sql "$CONNECT_STRING" "select pdb_name from dba_pdbs;") || { echo "SQL Error" ; echo "$ret" ; return 1 ; }
  [ "${ret}" = "${1^^}" ] && echo "OK" || { echo "*** ERROR *** (ret=$ret)" ; return 1 ; }
  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
checkDir()
{
  printf "%-75s : " "  - Existence of $1"
  if [ ! -d $1 ]
  then
    echo "Non Existent"
    printf "%-75s : " "    - Creation of $1"
    mkdir -p $1 && echo OK || { echo "*** ERROR ***" ; return 1 ; }
  else
    echo "OK"
  fi
  printf "%-75s : " "    - $1 is writable"
  [ -w $1 ] && echo OK || { echo "*** ERROR ***" ; return 1 ; }
  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
checkORADir()
{
  printf "%-75s : " "  - Existence of $1"
  ret=$(exec_sql "$CONNECT_STRING" "select 'OK' from dba_directories where directory_name='$1' and directory_path='$2';") || { echo "SQL Error" ; echo "$ret" ; return 1 ; }
  if [ "$ret" != "OK" ]
  then
    echo "Non Existent (ret=$ret)"
    exec_sql "$CONNECT_STRING" "create or replace directory $1 as '$2';" "    - Creation of $1 --> $2"
    return $?
  else
    echo "OK"
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
createParFile()
{
  printf "%-75s : " "  - Creating Parameter File"
  rm -f $PARFILE
  echo "
DIRECTORY=$ORA_EXPDIR
SCHEMAS=BNA
LOGFILE=bnaExp_${DAT_EXP}.log
DUMPFILE=bnaExp_${DAT_EXP}_%U.dmp
FILESIZE=45GB
COMPRESSION=ALL
PARALLEL=12
flashback_time=systimestamp
  " > $PARFILE && { echo "OK" ; return 0 ; }  || { echo "*** ERROR ***" ; return 1 ; } 
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set -o pipefail

#
#      Database information
#
SCAN_NAME=prdexacs-pcccs-scan.dbarg.prd.oraclevcn.com        # Adress of SCAN LISTENER
SCAN_PORT=1521                                               # LISTENER Port
SERVICE_NAME=bna0ppr.dbarg.prd.oraclevcn.com                 # PDB service name
USERNAME="C##MBOORA"                                         # DBA user used for export
PASSWORD=${PASSWORD:-""}                                     # User's PASSWORD, (can be set in the environment), asked if not set


PDB_NAME="BNA0PPR"                                           # PDB Name
DO_EXPORT=Y                                                  # Set to N to avoid export

PHYSICAL_DIR=/admindb/expbna                                 # EXPORT DIR (must be clustered
ORA_EXPDIR=EXPBNA_DMP                                        # ORACLE Directory NAME
DAT_EXP=$(date +%Y%m%d_%H%M)                                 # Export DATE (for filenames)
LOG_FILE=$PHYSICAL_DIR/log/expBNA$(date +%Y%m%d_%H%M%S).log  # This script's log

PARFILE=$PHYSICAL_DIR/parfile/expBNA.par                     # Parameter file name (script generated)

if [ "$PASSWORD" = "" ]
then
  echo "PASSWORD not set ..."
  read -s -p "Please enter the password for $USERNAME : " PASSWORD
fi

CONNECT_STRING="\"$USERNAME\"/\"$PASSWORD\"@//$SCAN_NAME:$SCAN_PORT/$SERVICE_NAME"

checkDir $PHYSICAL_DIR/dmp || die "$PHYSICAL_DIR/dmp is incorrect"
checkDir $PHYSICAL_DIR/log || die "$PHYSICAL_DIR/log is incorrect"
checkDir $PHYSICAL_DIR/parfile || die "$PHYSICAL_DIR/parfile is incorrect"

{
  echo "
+===================================================================================
|
|      Export of the BNA Schema for OAC
|
|      Script LOG in : $LOG_FILE
|
+===================================================================================
  "

  echo
  echo "DB Connection check"
  echo

  exec_sql "$CONNECT_STRING" "select 1 from dual ;" "  - Testing DATABASE CONNECT String" || die "Unable to connect to the database"
  testPDB $PDB_NAME || die "Not connected to $PDB_NAME PDB"

  echo
  echo "Pre-Export tasks"
  echo
  checkORADir $ORA_EXPDIR $PHYSICAL_DIR/dmp || die "ORACLE Directory ($ORA_EXPDIR) is incorrect or non-existent"
  createParFile || die "Unable to create the parameter file"

  START_INTERM_EPOCH=$(date +%s)
  echo   "========================================================================================" 
  echo   "  - export"
  echo   "  - Started at     : $(date)"
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "

  [ "$DO_EXPORT" = "Y" ] && expdp "$USERNAME/\"$PASSWORD\"@//$SCAN_NAME:$SCAN_PORT/$SERVICE_NAME" PARFILE=$PARFILE

  END_INTERM_EPOCH=$(date +%s)
  all_secs2=$(expr $END_INTERM_EPOCH - $START_INTERM_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')

  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "  - Ended at      : $(date)" 
  echo   "  - Duration      : ${mins2}:${secs2}"
  echo   "========================================================================================" 


} 2>&1 | tee $LOG_FILE

  echo
  echo "Clean logs directory"
  echo "   --> $PHYSICAL_DIR/log" 
  echo
i=0
ls -1t $PHYSICAL_DIR/log/expBNA*  | while read f
do
  i=$(($i + 1))
  if [ $i -gt 5 ]
  then
    echo "Remove $f"
    rm -f $f
  fi
done

echo "


     Script's LOG : $LOG_FILE"
