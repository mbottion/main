#!/bin/bash

# ================== Start generic Variables (do not remove or change this line)==================
dbUniqueName=
pdbName=
bucketName=
# ================== End generic Variables (do not remove or change this line) ==================
usage() {
 echo "Usage :
 $SCRIPT [-?] [-d dbName] [-p pdbName] [-H] {scriptCode|scriptPath}
   -?           : Help
   -H           : html output
   scriptCode   : Code for frequent scripts
   scriptPath   : Full path

   Download a script from gitHup and run it under sqlplus
  "
}
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}

SCRIPT=runSQL.sh

outputType=txt 
toShift=0
while getopts "d:p:H?" opt
do
  case $opt in
    d) dbUniqueName=$OPTARG ; toShift=$(($toShift + 2)) ;;
    p) pdbName=$OPTARG ; toShift=$(($toShift + 2)) ;;
    H) outputType=html ; toShift=$(($toShift + 1)) ;;
    ?|h) shift ; usage ;;
  esac
done
shift $toShift


gitHub=https://raw.githubusercontent.com/mbottion

[ "$1" = "" ] && die "No script or script code to run"
case ${1^^} in
  LONGOPS) scriptName=SQLTools/main/longOps.sql ;;
  TBSUSAGE) scriptName=SQLTools/main/tbsUsage.sql ;;
  *) die "No valid code"
esac

fullName=$gitHub/$scriptName
curl -fsLO $fullName >/dev/null 2>&1  || die "Unable to access $fullName"



envOk=N
if  [ -f /etc/oratab ]
then
  if [ "$(grep "^${dbUniqueName}:" /etc/oratab)" != "" ]
  then
    echo "  - $dbUniqueName found in oratab, set environment..."
    . oraenv  <<< $dbUniqueName >/dev/null
    ORACLE_UNQNAME=$ORACLE_SID
    ORACLE_SID=$(srvctl status database -d $ORACLE_UNQNAME | \
                     grep -i $(hostname -s) |  cut -f2 -d " ")
    envOk=Y
  fi
fi
if [ "$envOk" = "N" -a -f "$HOME/$dbUniqueName.env" ]
then
  echo "  - Env file found "
  . $HOME/$dbUniqueName.env
  envOk=Y
fi


[ "$envOk" = "N" ] && die "Unable to set environment for $dbUniqueName"

f=$(sqlplus -s / as sysdba <<%%
set feed off heading off pages 0 feedback off
whenever sqlerror exit failure
alter session set container=$pdbName ;
select to_char(sysdate,'yyyymmdd_hh24miss') || '_' || lower(d.name) || '_' 
                      || replace(sys_context('USERENV','CON_NAME'),'$','_') 
from dual,v\$database d ;
%%
) || die "Error getting the file name from database"

outputFile=/tmp/$(basename $scriptName .sql)_$f.$outputType
spoolOnCommand="spool $outputFile"
spoolOffCommand="spool off"

if [ "$outputType" = "html" ]
then
  termoutCommand="set term off"
  sqlplusFormatCommand="set markup HTML ON 
set feed off"
fi

tmpSQLScript=/tmp/$$.tmp.sql
echo "
whenever sqlerror exit failure
whenever oserror exit failure
set feedback off
alter session set container=$pdbName ;
$termoutCommand
$sqlplusFormatCommand
$spoolOnCommand
$(curl -sL $gitHub/$scriptName)
$spoolOffCommand
exit
" > $tmpSQLScript

sqlplus -s / as sysdba @$tmpSQLScript || { rm -f $tmpSQLScript ; die "Error executing the script" ; }
rm -f $tmpSQLScript

echo "Sending $outputFile to Object Storage"
curl -T $outputFile $bucketName

rm -f $outputFile

