#!/bin/bash

# ================== Start generic Variables (do not remove or change this line)==================
dbUniqueName=prd02exa_fra1w2
pdbName=bna0ppr
bucketName=https://objectstorage.eu-frankfurt-1.oraclecloud.com/p/P0kG7DEFRA5RsAs3HG9ofzufmljEMd_0pwVLD0GNh5KqOuw4qe0Q6woMSLFpVkNB/n/cnafsi/b/MBO/o/
gitHubToken=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
# ================== End generic Variables (do not remove or change this line) ==================
usage() {
 echo "Usage :
 $SCRIPT [-?] [-d dbName] [-p pdbName] [-H] [-i] [-g] [-l] {scriptCode|scriptPath [scriptParams]}
   -?           : Help
   -H           : html output
   -i           : screen output only
   -g           : get script
   -l           : Upload script to gitHub
   scriptCode   : Code for frequent scripts
   scriptPath   : Full path
   scriptParams : Parameters of the script (try HELP)

   Download a script from gitHup and run it under sqlplus
  "
  exit
}
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}

scriptExists()
{
  local f=$1
  curl -fsL $f >/dev/null 2>&1
  return $?
}

uploadToGitHub ()
{
  local f=$1
  local r=$2
  local t=$3
  local fs=$(basename $f)
  local gitFile=$gitHub/$r/main/$fs
  local apiFile=https://api.github.com/repos/mbottion/$r/contents/$fs
  
  if scriptExists $gitFile
  then
    echo "File Exists in gitHub"
    sha=$(curl -s -X GET $apiFile | grep "sha" | cut -f2 -d: | cut -f2 -d"\"")
    echo "update the file"
    #
    #  Clean-up file (avoid posting personal information or token)
    #
    cp -p $f $f.tmp
    for var in dbUniqueName pdbName bucketName gitHubToken
    do
      echo "Removing $var value"
      sed -i "s;^\($var=\).*;\1" $f.tmp
    done
    local json="
{\
  \"path\" : \"$fs\", \
  \"message\" : \"Updated by $SCRIPT\", \
  \"content\" : \"$(base64 $f.tmp | tr '\n' ' ' | sed -e "s; ;;g")\", \
  \"sha\" : \"$sha\" \
}"
    rm -f $f.tmp
    
    curl -v -i -X PUT -H "Authorization: token $gitHubToken" \
         -d "$json" $apiFile
  else
    echo "File do not Exists in gitHub"
  fi
  
}

SCRIPT=runSQL.sh

outputType=txt 
screenOutputOnly=N
toShift=0
getScriptOnly=N
uploadScriptOnly=N
while getopts "d:p:Higl?" opt
do
  case $opt in
    d) dbUniqueName=$OPTARG ; toShift=$(($toShift + 2)) ;;
    p) pdbName=$OPTARG      ; toShift=$(($toShift + 2)) ;;
    H) outputType=html      ; toShift=$(($toShift + 1)) ;;
    i) screenOutputOnly=Y   ; toShift=$(($toShift + 1)) ;;
    g) getScriptOnly=Y      ; toShift=$(($toShift + 1)) ;;
    l) uploadScriptOnly=Y      ; toShift=$(($toShift + 1)) ;;
    ?|h) shift ; usage ;;
  esac
done
shift $toShift


gitHub=https://raw.githubusercontent.com/mbottion

[ "$1" = "" ] && die "No script or script code to run"
case ${1^^} in
  LONGOPS) scriptName=SQLTools/main/longOps.sql ;;
  TBSUSAGE) scriptName=SQLTools/main/tbsUsage.sql ;;
  DISKSPERCELL) scriptName=ASMTools/main/disksPerCell.sql ;;
  OPAREGIS) scriptName=CNAFTools/main/OPARegis.sql ;;
  *) if [ -f $1 ]
     then
       fullName="file://$(readlink -f $1)"
     elif [ "$(echo ${1^^} | cut -c 1-4)" = "HTTP" ]
     then
       fullName=$1
     else
       die "Non recognized file name or code : $1"
     fi
     ;;
esac

if  [ "$uploadScriptOnly" = "Y" ]
then
  [  -f "$1" ] || die "Upload : file: $1 non-existent"
  [  "$2" != "" ] || die "Upload : Repository name needed"
  [  "$gitHubToken" != "" ] || die "Upload : gitHubToken Required"
  uploadToGitHub $1 $2 $gitHubToken
  exit 0
fi


shift
scriptParameters="$*"

[ "$fullName" = "" ] && fullName=$gitHub/$scriptName
scriptExists $fullName || die "Unable to access $fullName"

if  [ "$getScriptOnly" = "Y" ]
then
  curl -fsLO $fullName >/dev/null
  exit 0
fi


envOk=N
echo
echo "Set the environment"
echo "==================="
if  [ -f /etc/oratab ]
then
  if [ "$(grep "^${dbUniqueName}:" /etc/oratab)" != "" ]
  then
    echo "    - $dbUniqueName found in oratab, set environment..."
    . oraenv  <<< $dbUniqueName >/dev/null
    ORACLE_UNQNAME=$ORACLE_SID
    ORACLE_SID=$(srvctl status database -d $ORACLE_UNQNAME | \
                     grep -i $(hostname -s) |  cut -f2 -d " ")
    envOk=Y
  fi
fi
if [ "$envOk" = "N" -a -f "$HOME/$dbUniqueName.env" ]
then
  echo "    - Env file found "
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

outputFile=/tmp/$(basename $fullName .sql)_$f.$outputType
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

set term off
set feed off
set verify off
column 1 new_value 1 
column 2 new_value 2 
column 3 new_value 3 
column 4 new_value 4 
column 5 new_value 5 
column 6 new_value 6 
column 7 new_value 7 
column 8 new_value 8 
column 9 new_value 9 

select '' \"1\", '' \"2\", '' \"3\", '' \"4\",'' \"5\", '' \"6\", '' \"7\", '' \"8\",'' \"9\" from dual where 1=2 ;
set term on feed on lines 2000 trimout on pages 50000


$termoutCommand
$sqlplusFormatCommand
$spoolOnCommand
$(curl -sL $fullName)
$spoolOffCommand
exit
" > $tmpSQLScript

echo
echo "Running the script : $fullName"
echo "=================="
echo
sqlplus -s / as sysdba @$tmpSQLScript $scriptParameters || { rm -f $tmpSQLScript ; die "Error executing the script" ; }
rm -f $tmpSQLScript

echo
if [ "$screenOutputOnly" = "N" ]
then
  echo "Send Output"
  echo "==========="
  echo "    - Sending $outputFile to Object Storage"
  echo
  curl -T $outputFile $bucketName
fi

rm -f $outputFile

