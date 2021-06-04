
deletePdb()
{

  echo "
+===================================================================================
|
|      Suppression PDB $dstPdbName
|
+===================================================================================
  "


  START_INTERM_EPOCH=$(date +%s)
  echo   "========================================================================================" 
  echo   "  - Preparation"
  echo   "  - Started at     : $(date)"
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "

  echo   " Base cible "
  echo   " =========== "
  echo   "    CDB          : $dstDbName"
  echo   "    PDB          : $dstPdbName"
# 
# -----------------------------------------------------------------------------------------
# 
  startStep "Verifications et preparation"

  exec_sql "/ as sysdba " "select 1 from dual ;" "  - Connexion SYSDBA a la cible" || die "Unable to connect to the database"
  res=$(exec_sql "/ as sysdba" "select 1 from v\$pdbs where name=upper('$dstPdbName');") || die "Erreur select PDB cible ($res)"
  printf "%-75s : " "  - Existence PDB Cible ($dstPdbName)" ; [ "$res" = "" ] && { echo "Non existante" ; dstPdbExists=N ; die "PDB Inexistante" ; }  || { echo "Existante" ; dstPdbExists=Y ; }
  endStep
# 
# -----------------------------------------------------------------------------------------
# 
  startStep "Suppression PDB"
  
      exec_sql "/ as sysdba " "alter pluggable database $dstPdbName close immediate instances=all ; " "     - Fermeture PDB" || die
      exec_sql "/ as sysdba " "drop pluggable database $dstPdbName including datafiles ; " "     - Suppression PDB" || die
  endStep
# 
# -----------------------------------------------------------------------------------------
# 
  echo
  END_INTERM_EPOCH=$(date +%s)
  all_secs2=$(expr $END_INTERM_EPOCH - $START_INTERM_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "  - Ended at      : $(date)" 
  echo   "  - Duration      : ${mins2}:${secs2}"
  echo   "========================================================================================" 
  echo   "Script LOG in : $LOG_FILE"
  echo   "========================================================================================" 
}

copyAndMigrate()
{
  echo "
+===================================================================================
|
|      Copie et migration DB
|
+===================================================================================
  "

  START_INTERM_EPOCH=$(date +%s)
  echo   "========================================================================================" 
  echo   "  - Preparation"
  echo   "  - Started at     : $(date)"
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "

  echo   " Base Source "
  echo   " =========== "
  echo   "    CDB          : $srcDbName"
  echo   "    PDB          : $srcPdbName"
  echo   "    Scan         : $SCAN_NAME:$SCAN_PORT"
  echo   "    Service      : $SERVICE_NAME"
  echo   "    Connect      : $SRC_CONNECT_STRING"
  echo   " Base cible "
  echo   " =========== "
  echo   "    CDB          : $dstDbName"
  echo   "    PDB          : $dstPdbName"
# 
# -----------------------------------------------------------------------------------------
# 

startStep "Verifications et preparation"

  exec_sql "/ as sysdba " "select 1 from dual ;" "  - Connexion SYSDBA a la cible" || die "Unable to connect to the database"
  exec_sql "$SRC_CONNECT_STRING" "select 1 from dual ;" "  - Connexion $MIG_USER a la source" || die "Unable to connect to the database"

  echo

  exec_sql -no_error "/ as sysdba" "drop database link $DBLINK ; " "  - Suppression database link $DBLINK" 
  exec_sql           "/ as sysdba" "
create database link $DBLINK 
connect to $MIG_USER identified by \"$MIG_PASS\" 
using '//$SCAN_NAME/$SERVICE_NAME:$SCAN_PORT' ;" "  - Creation database link $DBLINK" || die "Impossible  de creer le DATABASE LINK"

  exec_sql "/ as sysdba" "alter system set global_names=FALSE scope=memory ;" "  - Global_names=false (memory)" || die "Impossble de changer la valeur"
  exec_sql "/ as sysdba" "select dummy from dual@$DBLINK;" "  - Verification du DBLINK" || die "Impossble de lire via $DBLINK"


  echo

  res=$(exec_sql "/ as sysdba" "select 1 from cdb_pdbs where pdb_name=upper('$dstPdbName');") || die "Erreur select PDB cible ($res)"
  printf "%-75s : " "  - Existence PDB Cible ($dstPdbName)" ; [ "$res" = "" ] && { echo "Non existante" ; dstPdbExists=N ; }  || { echo "Existante" ; dstPdbExists=Y ; }

  res=$(exec_sql "$SRC_CONNECT_STRING" "select 1 from cdb_pdbs where pdb_name=upper('$srcPdbName');") || die "Erreur select PDB SOurce ($res)"
  printf "%-75s : " "  - Existence PDB Source ($srcPdbName)" ; [ "$res" = "" ] && { echo "Non existante" ; srcPdbExists=N ; die "La PDB Source n'existe pas" ; }  || { echo "Existante" ; srcPdbExists=Y ; }

  endStep 
# 
# -----------------------------------------------------------------------------------------
# 

  startStep "Recopie de la PDB"
  

  if [ "$dstPdbExists" = "N" ]
  then
    exec_sql "/ as sysdba " "
create pluggable database $dstPdbName
from  ${srcPdbName}@$DBLINK PARALLEL 10
keystore identified by \"$keyStorePassword\" ;" "     - Recopie de ${srcPdbName}@$DBLINK dans $dstPdbName" || die "Erreur de copie de la PDB"
  else
    echo "     - la PDB existe deja"
  fi
                            
  endStep 
# 
# -----------------------------------------------------------------------------------------
# 
  startStep "Upgrade de la PDB"


    openMode=$(exec_sql "/ as sysdba" "select open_mode from v\$pdbs where name=upper('$dstPdbName');")
    if [ "$openMode" = "READ WRITE" ]
    then
      echo "     - La base est ouverte, on ne fait rien"
    else
      exec_sql "/ as sysdba " "alter pluggable database $dstPdbName close immediate instances=all ; " "     - Fermeture PDB" || die
      exec_sql "/ as sysdba " "alter pluggable database $dstPdbName open ; " "     - Tentative d'ouverture" || die
      openMode=$(exec_sql "/ as sysdba" "select open_mode from v\$pdbs where name=upper('$dstPdbName');")
      echo "       ====> [$openMode]"
      if [ "$openMode" = "MIGRATE" ]
      then
        echo "     - Upgrade ....."
        dbupgrade -c $dstPdbName 2>&1 | sed -e "s;^;          ;" || die "Erreur d'upgrade"
      elif [ "$openMode" = "READ WRITE" ]
      then
        echo "     - La base est ouverte, on ne fait rien"
      else
        echo "       =====> Et là, on fait quoi?????"
      fi
    fi

  endStep 
# 
# -----------------------------------------------------------------------------------------
# 
  startStep "Controles et ouverture"
  exec_sql "/ as sysdba" "

clear columns
set lines 200
set pages 200
col message format a55
col status format a10
col action format a55
col time format a30
set recsep off
set tab off

select message,time,status,action from pdb_plug_in_violations ;"

  exec_sql "/ as sysdba" "alter pluggable database $dstPbdName close immediate instances = all;" "     - Fermeture PDB"
  exec_sql "/ as sysdba" "alter pluggable database $dstPbdName open;" "     - Ouverture PDB"
  exec_sql "/ as sysdba" "alter pluggable database $dstPbdName save state;" "     - Enregistrement etat"
  endStep 
# 
# -----------------------------------------------------------------------------------------
# 

  END_INTERM_EPOCH=$(date +%s)
  all_secs2=$(expr $END_INTERM_EPOCH - $START_INTERM_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "  - Ended at      : $(date)" 
  echo   "  - Duration      : ${mins2}:${secs2}"
  echo   "========================================================================================" 
  echo   "Script LOG in : $LOG_FILE"
  echo   "========================================================================================" 
}

startStep()
{
  STEP="$1"
  STEP_START_EPOCH=$(date +%s)
  echo
  echo " $STEP"
  echo " ================================================================="
  echo   "     - Demarrage a   : $(date)" 
  echo
}
endStep()
{
  STEP_END_EPOCH=$(date +%s)
  all_secs2=$(expr $STEP_END_EPOCH - $STEP_START_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo
  echo   "     - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "     - Etape         : $STEP"
  echo   "     - Terminee a    : $(date)" 
  echo   "     - Duree         : ${mins2}:${secs2}"
  echo   "     - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

usage() {
 echo "Usage :
 $SCRIPT [-?] [-u srcDbName] [-p srcPdbName] [-U dstDbName] [-P dstPdbName] [-k keyStorePass] [-C|-M|-A|-D]
   -?           : Help
  "
  exit
}


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
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set -o pipefail

[ "$1" = "" ] && usage

while getopts :u:p:U:P:k:CD opt
do
  case $opt in
   u)   srcDbName=$OPTARG        ; toShift=$(($toShift + 2)) ;;
   p)   srcPdbName=$OPTARG       ; toShift=$(($toShift + 2)) ;;
   U)   dstDbName=$OPTARG        ; toShift=$(($toShift + 2)) ;;
   P)   dstPdbName=$OPTARG       ; toShift=$(($toShift + 2)) ;;
   k)   keyStorePassword=$OPTARG ; toShift=$(($toShift + 2)) ;;
   C)   mode=COPY                ; toShift=$(($toShift + 1)) ;;
   D)   mode=DELETE              ; toShift=$(($toShift + 1)) ;;
   ?|h) usage ;;
  esac
done
shift $toSift 

srcDbName=${srcDbName:-tmpmig_fra15w}
srcPdbName=${srcPdbName:-TST1}
dstDbName=${dstDbName:-tstmig}
dstPdbName=${dstPdbName:-TMP1}
keyStorePassword=${keyStorePassword:-Wel_Come_12}
mode=${mode:-COPY}
SCAN_NAME=${SCAN_NAME:-hprexacs-7sl1q-scan.dbad2.hpr.oraclevcn.com}
SCAN_PORT=1521
DOMAIN=dbad2.hpr.oraclevcn.com
SERVICE_NAME=$srcDbName.$DOMAIN
DBLINK=pdbclone

[ -f "$HOME/$dstDbName.env" ] || die "$dstDbName.env non existent"
. "$HOME/$dstDbName.env"
[ "$(exec_sql "/ as sysdba" "select  name from v\$database;")" != "${dstDbName^^}" ] && die "Environnement mal positionne"

DAT=$(date +%Y%m%d_%H%M)                                 # Export DATE (for filenames)
BASEDIR=$HOME/migate19                                  # Base dir for logs & files
MIG_DIR=$BASEDIR/$srcDbName
LOG_DIR=$MIG_DIR/log
case $mode in
  COPY)      LOG_FILE=$LOG_DIR/migRun_MIG_${dstDbName}_${dstPdbName}_${DAT}.log ;;
  DELETE)    LOG_FILE=$LOG_DIR/migRun_DEL_${dstDbName}_${dstPdbName}_${DAT}.log ;;
  *)                    die "Mode inconnu"
esac

MIG_USER="C##PDBCLONE"
MIG_PASS="Wel_Come_12"


SRC_CONNECT_STRING="\"$MIG_USER\"/\"$MIG_PASS\"@//$SCAN_NAME:$SCAN_PORT/$SERVICE_NAME"

checkDir $LOG_DIR || die "$LOG_DIR is incorrect"

case $mode in
 COPY) copyAndMigrate 2>&1 | tee $LOG_FILE ;;
 DELETE) deletePdb 2>&1 | tee $LOG_FILE ;;
esac

