VERSION=0.1
_____________________________TraceFormating() { : ;}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#     Trace
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Usage
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
usage() 
{
 echo "$SCRIPT :

Usage :
 $SCRIPT [-n] [-h|-?]

      $SCRIPT_LIB
         -n           : Don't log the output to file
         -?|-h        : Help

  Version : $VERSION
  "
  exit
}
libAction()
{
  local mess="$1"
  local indent="$2"
  [ "$indent" = "" ] && indent="  - "
  printf "%-90.90s : " "${indent}${mess}"
}
infoAction()
{
  local mess="$1"
  local indent="$2"
  [ "$indent" = "" ] && indent="  - "
  printf "%-s\n" "${indent}${mess}"
}
startRun()
{
  START_INTERM_EPOCH=$(date +%s)
  START_INTERM_FMT=$(date +"%d/%m/%Y %H:%M:%S")
  echo   "========================================================================================"
  echo   " Execution start"
  echo   "========================================================================================"
  echo   "  - $1"
  echo   "  - Started at     : $START_INTERM_FMT"
  echo   "========================================================================================"
  echo
}
endRun()
{
  END_INTERM_EPOCH=$(date +%s)
  END_INTERM_FMT=$(date +"%d/%m/%Y %H:%M:%S")
  all_secs2=$(expr $END_INTERM_EPOCH - $START_INTERM_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo
  echo   "========================================================================================"
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "  - Ended at      : $END_INTERM_FMT"
  echo   "  - Duration      : ${mins2}:${secs2}"
  echo   "========================================================================================"
  echo   "Script LOG in : $LOG_FILE"
  echo   "========================================================================================"
  if [ "$CMD_FILE" != "" ]
  then
    echo   "Commands Logged to : $CMD_FILE"
    echo   "========================================================================================"
  fi
}
startStep()
{
  STEP="$1"
  STEP_START_EPOCH=$(date +%s)
  echo
  echo "       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo "       - Step (start)  : $STEP"
  echo "       - Started at    : $(date)"
  echo "       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo
}
endStep()
{
  STEP_END_EPOCH=$(date +%s)
  all_secs2=$(expr $STEP_END_EPOCH - $STEP_START_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo
  echo "       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo "       - Step (end)    : $STEP"
  echo "       - Ended at      : $(date)"
  echo "       - Duration      : ${mins2}:${secs2}"
  echo "       - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
}
die()
{
  [ "$START_INTERM_EPOCH" != "" ] && endRun
  echo "
ERROR :
  $*"

  rm -f $PID_FILE

  exit 1
}
_____________________________Environment() { : ;}
setASMEnv()
{
  libAction "Set ASM environment"
  . oraenv <<< +ASM1 >$TMP1 2>&1 && echo "OK" || { echo ERROR ; cat $TMP1 ; rm -f $TMP1 ; die "Unable to set environment for ASM" ; }
}
setDbEnv()
{
  libAction "Set $1 environment"
  . $HOME/$1.env && echo OK || { echo ERROR ; die "Unable to set database envirronment" ; } 
}
setScriptEnv()
{
echo "
    +--------------------------------------------------------------------------------+
    |   Set main script environment variables                                        |
    +--------------------------------------------------------------------------------+
      ACTION=$ACTION
"
  if [    "$(echo $ACTION | cut -c1-5)" != "TRACK" \
       -a "$ACTION" != "CLONE_LIST" \
       -a "$ACTION" != "TM_STATUS" \
       -a "$ACTION" != "TM_STOP" \
     ] 
  then
    setASMEnv
    SPARSE_DG=$(exec_sql "/ as sysdba" "
SELECT
  name
FROM
  v\$asm_diskgroup
WHERE
  group_number IN (
    SELECT
      group_number
    FROM
      v\$asm_diskgroup_sparse
  ); 
") || die "Databse Error ($SPARSE_DG)"
    libAction "SPARSE Disk Group" ; echo "$SPARSE_DG"
    [ "$SPARSE_DG" = "" ] && die "No sparse disk group found"
    
    DATA_DG=$(exec_sql "/ as sysdba" "
SELECT
  name
FROM
  v\$asm_diskgroup
WHERE
  group_number NOT IN (
    SELECT
      group_number
    FROM
      v\$asm_diskgroup_sparse
  ) and name like '%DATA%';
") || die "Databse Error ($DATA_DG)"

    RECO_DG=$(exec_sql "/ as sysdba" "
SELECT
  name
FROM
  v\$asm_diskgroup
WHERE
  group_number NOT IN (
    SELECT
      group_number
    FROM
      v\$asm_diskgroup_sparse
  ) and name like '%RECO%';
") || die "Databse Error ($RECO_DG)"

    libAction "DATA Disk Group" ; echo "$DATA_DG"
    libAction "RECO Disk Group" ; echo "$RECO_DG"
  fi
  
  setDbEnv $SOURCE_STANDBY
  
  DB_PASSWORD=$(getPassDB)
  DO_TRACKING=$(trackingTest)
  
  case $SOURCE_STANDBY in
    *AME*) ZONE=1 ;;
    *EUR*) ZONE=2 ;;
    *ACJ*) ZONE=3 ;;
    *MBO*) ZONE=4 ;;
    *)     ZONE=0 ;;
  esac
  
  TEST_MASTER="TM${ZONE}${SUFFIX}"
  TM_UNIQUE_NAME="${TEST_MASTER}_TM${ZONE}_${SUFFIX}"
}
showEnv()
{
echo "

   Environment variable used (ACTION=$ACTION):
   
   Database information:
   ====================
   
   SOURCE_STANDBY                    : $SOURCE_STANDBY
   ORACLE_UNQNAME                    : $ORACLE_UNQNAME
   DATA_DG                           : $DATA_DG    
   RECO_DG                           : $RECO_DG    
   SPARSE_DG                         : $SPARSE_DG  
   DB_PASSWORD                       : $( test -z "$DB_PASSWORD" && echo "Not Found" || echo "Set")
   
   Test Master Operations
   ======================
   
   SUFFIX                            : $SUFFIX
   ZONE                              : $ZONE
   TEST_MASTER                       : $TEST_MASTER
   TM_UNIQUE_NAME                    : $TM_UNIQUE_NAME
   
   Script Behaviour:
   ================
   
   DO_TRACKING                       : $DO_TRACKING  
   LOG_DIR                           : $LOG_DIR
   INFO_DIR                          : $INFO_DIR
"
}
_____________________________Utilities() { : ;}
getPassDB()
{
  local dir=""
  if [ -d /acfs01/dbaas_acfs/$ORACLE_UNQNAME/db_wallet ]
  then
    dir=/acfs01/dbaas_acfs/$ORACLE_UNQNAME/db_wallet
  elif [ -d /acfs01/dbaas_acfs/$ORACLE_SID/db_wallet ]
  then
    dir=/acfs01/dbaas_acfs/$ORACLE_SID/db_wallet
  elif [ -d /acfs01/dbaas_acfs/$(echo $ORACLE_SID|sed -e "s;.$;;")/db_wallet ]
  then
    dir=/acfs01/dbaas_acfs/$(echo $ORACLE_SID|sed -e "s;.$;;")/db_wallet
  else
    echo
  fi
  mkstore -wrl $dir -viewEntry passwd | grep passwd | sed -e "s;^ *passwd = ;;"
}
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
  local loginSecret=$(echo "$login" | sed -e "s;/[^@ ]*;/SecretPasswordToChange;" -e "s;^/SecretPasswordToChange;/;")
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
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
SQLPLUS : ${lib:-No description}
===============================================================================
sqlplus \"$loginSecret\" <<%%
$bloc_sql
%%
    " >> $CMD_FILE
  fi
  REDIR_FILE=""
  REDIR_FILE=$(mktemp)
  if [ "$lib" != "" ] 
  then
     libAction "$lib"
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
                      || { echo "OK" ; [ "$VERBOSE" = "Y" ] && test -f $REDIR_FILE && sed -e "s;^;    > ;" $REDIR_FILE ; }
  fi 
  rm -f $REDIR_FILE
  [ $status -ne 0 ] && return 1
  return $status
}
exec_srvctl()
{
  SILENT=N
  [ "$1" = "-silent" ] &&  { local SILENT=Y ; shift ; }
  local cmd=$1
  local lib=$2
  local okMessage=$3
  local koMessage=$4
  local dieMessage=$5
  local tmpOut=${TMPDIR:-/tmp}/$$.tmp
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
SRVCTL : ${lib:-No description}
===============================================================================
srvctl $cmd
    " >> $CMD_FILE
  fi
  [ "$lib" != "" ] &&  libAction "$lib"
  if srvctl $cmd > $tmpOut 2>&1
  then
    [ "$lib" != "" ] && echo "${okMessage:-OK}"
    [ "$lib" = "" ]  && cat "$tmpOut"
    rm -f "$tmpOut"
    return 0
  else
    [ "$lib" != "" ] && echo "${koMessage:-ERROR}"
    [ "$SILENT" = "N" ] && cat $tmpOut
    rm -f $tmpOut
    [ "$diemessage" = "" ] && return 1 || die "$dieMessage"
  fi
}
exec_dgmgrl()
{
  if [ "$3" != "" ]
  then
    local connect="$1"
    shift
  else
    local connect="sys/${dbPassword}@${primDbUniqueName}"
  fi
  local connectSecret=$(echo "$connect" | sed -e "s;/[^@ ]*;/SecretPasswordToChange;" -e "s;^/SecretPasswordToChange;/;")
  local cmd=$1
  local lib=$2
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
DGMGRL : ${lib:-No description}
===============================================================================
dgmgrl -silent \"$connectSecret\" \"$cmd\"
    " >> $CMD_FILE
  fi
  # echo "    - $cmd"
  [ "$lib" != "" ] && libAction "$lib"
  dgmgrl -silent "$connect" "$cmd" > $$.tmp 2>&1 \
    && { [ "$lib" != "" ] && echo "OK" ; [ "$lib" = "" ] && cat $$.tmp ; rm -f $$.tmp ; return 0 ; } \
    || { [ "$lib" != "" ] && echo "ERROR" ; cat $$.tmp ; rm -f $$.tmp ; return 1 ; }
}
exec_asmcmd()
{
  local cmd=$1
  local lib=$2
  local okMessage=${3:-OK}
  local koMessage=${4:-ERROR}
  local dieMessage=$5
  local tmpOut=${TMPDIR:-/tmp}/$$.tmp
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
ASMCMD : ${lib:-No description}
===============================================================================
asmcmd --privilege sysdba $cmd
    " >> $CMD_FILE
  fi

  libAction "$lib"
  if asmcmd --privilege sysdba $cmd > $tmpOut 2>&1
  then
    echo "$okMessage"
    rm -f $tmpOut
    return 0
  else
    echo "$koMessage"
    cat $tmpOut
    rm -f $tmpOut
    [ "$diemessage" = "" ] && return 1 || die "$dieMessage"
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
createASMDir()
{
  libAction "Creating $1" "    - "
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
ASMCMD : Creating $1 If non existent
===============================================================================
asmcmd --privilege sysdba mkdir $1
    " >> $CMD_FILE
  fi
  if [ "$(asmcmd --privilege sysdba ls -ld $1)" = "" ] 
  then
    asmcmd --privilege sysdba mkdir $1 > $TMP1 2>&1 \
                && { echo "OK" ; rm -f $TMP1 ; } \
                || { echo "ERROR" ; cat $TMP1 ; rm -f $TMP1 ; die "Unable to create $1" ; }
  else
    echo "Exists"
  fi
}
removeASMDir()
{
  libAction "Removing ASM Folder $1" "    - "
  if [ "$CMD_FILE" != "" ]
  then
    echo "\
===============================================================================
ASMCMD : Removing ASM Folder $1
===============================================================================
asmcmd --privilege sysdba rm -rf $1
    " >> $CMD_FILE
  fi
  if [ "$(asmcmd --privilege sysdba ls -ld $1 2>/dev/null)" != "" ] 
  then
    asmcmd --privilege sysdba rm -rf $1 > $TMP1 2>&1 \
                && { echo "OK" ; rm -f $TMP1 ; } \
                || { echo "ERROR" ; cat $TMP1 ; rm -f $TMP1 ; die "Unable to remove $1" ; }
  else
    echo "Not exists"
  fi
}

set -o pipefail

#if tty -s
if false
then
  die "Please run this script in nohup mode"
fi

_____________________________main() { : ; }

set -o pipefail

#if tty -s
if false
then
  die "Please run this script in nohup mode"
fi


set -o pipefail

SCRIPT=$(basename $0)
SCRIPT_BASE=$(basename $SCRIPT .sh)
SCRIPT_LIB="SHELL Script Template"

#[ "$(id -un)" != "oracle" ] && die "Merci de lancer ce script depuis l'utilisateur \"oracle\""
#[ "$(hostname -s | sed -e "s;.*\([0-9]\)$;\1;")" != "1" ] && die "Lancer ce script depuis le premier noeud du cluster"

# [ "$1" = "" ] && usage
toShift=0
while getopts nh opt
do
  case $opt in
   # --------- Source Database --------------------------------
   # --------- Target Database --------------------------------
   # --------- Modes de fonctionnement ------------------------
   # --------- Usage ------------------------------------------
   n)   logOutput=NO   ; toShift=$(($toShift + 1)) ;;
   ?|h) usage "Help requested";;
  esac
done
shift $toShift 
# -----------------------------------------------------------------------------
#
#       Analyse des paramètres et valeurs par défaut
#
# -----------------------------------------------------------------------------

LOG_DIR=$HOME/scriptsLOG/$SCRIPT_BASE/$SOURCE_STANDBY
LOG_FILE=$LOG_DIR/${SCRIPT_BASE}_ACTION_$(date +%Y%m%d_%H%M%S).log
CMD_FILE=$LOG_DIR/${SCRIPT_BASE}_ACTION_$(date +%Y%m%d_%H%M%S).cmd

[ "$logOutput" = "NO" ] && LOG_FILE=/dev/null

[ "$LOG_FILE" != "" -a "$LOG_FILE" != "/dev/null" ] && mkdir -p $LOG_DIR

[ "$OCI_CONFIG_FILE" = "" ] && OCI_CONFIG_FILE=$HOME/.oci/config
[ ! -f $OCI_CONFIG_FILE ] && die "UNable to find OCICLI config file"


{
  startRun "$SCRIPT_LIB"
  
  endRun
  
} | tee $LOG_FILE
finalStatus=$?
echo
echo "Cleaning LOGS"
echo "============="
echo
LOGS_TO_KEEP=10
i=0
ls -1t $LOG_DIR/*.log | while read f
do
  i=$(($i + 1))
  [ $i -gt $LOGS_TO_KEEP ] && { echo "  - Removing $f" ; rm -f $f ; }
done
i=0
ls -1t $LOG_DIR/*.cmd | while read f
do
  i=$(($i + 1))
  [ $i -gt $LOGS_TO_KEEP ] && { echo "  - Removing $f" ; rm -f $f ; }
done

exit $finalStatus

