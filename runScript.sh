#!/bin/bash

# ================== Start generic Variables (do not remove or change this line)==================
dbUniqueName=
pdbName=
bucketName=
gitHubToken=
gitHubUser=
# ================== End generic Variables (do not remove or change this line) ==================

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

usage() {
 echo "Usage :
 $SCRIPT [-?] [-d dbName] [-p pdbName] [-H] [-i] [-g] [-l] {scriptName [scriptParams]}
   -?           : Help
   -H           : html output
   -i           : screen output only
   -g           : get script
   -l           : Upload script to gitHub
   scriptName   : Single file name / partial path / fullPath 
   scriptParams : Parameters of the script (try HELP)

   Download a script from gitHub and run it under sqlplus
  "
  exit
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

die()
{
  [ "$1" != "" ] && echo -e "\n\n$SCRIPT : Error \n      $*\n\n"
  exit 1
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

scriptExists()
{
  local f=$1
  curl -fsL $f >/dev/null 2>&1
  return $?
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
#       Upload a file to gitHub, provided the authentication
#  token is defined in the corresponding variable
#

uploadToGitHub ()
{
  local f=$1
  local r=$2
  local t=$3
  local fs=$(basename $f)
  local gitFile=$gitHub/$r/main/$fs
  local apiFile=https://api.github.com/repos/$gitHubUser/$r/contents/$fs

  echo "Send file $f to gitHub"
  if scriptExists $gitFile
  then
    #
    #    Get SHA of the existing file
    #
    echo "  - File Exists in gitHub"
    sha=$(curl -s -X GET $apiFile | grep "sha" | cut -f2 -d: | cut -f2 -d"\"")
    sha_string=" , \"sha\" : \"$sha\""
  else
    echo "  - New file in gitHub"
    sha_string=""
  fi
  #
  #  Clean-up file (avoid posting personal information or token)
  #
  echo "  - Cleaning file"
  cp -p $f $f.tmp
  for var in dbUniqueName pdbName bucketName gitHubToken gitHubUser
  do
    echo "    - Removing $var value"
    sed -i "s;^\($var=\).*;\1;" $f.tmp || { rm -f $f.tmp ; die "Error modifying the file" ; }
  done

  #
  #     Build the JSON to upload
  #
  local json="
{\
    \"path\" : \"$fs\" \
   ,\"message\" : \"Updated by $SCRIPT\" \
   ,\"content\" : \"$(base64 $f.tmp | tr '\n' ' ' | sed -e "s; ;;g")\" \
   $sha_string
}"
  rm -f $f.tmp
 
  #
  #    Upload and commit the file (main branch)
  #   
  echo -n "  - Sending file --> "
  curl  -s -S -X PUT -w "\nERRORCODE=%{http_code}" -H "Authorization: token $gitHubToken" \
        -d "$json" $apiFile > /tmp/$$.tmp
  errCode=$(grep ERRORCODE /tmp/$$.tmp | cut -f2 -d"=")
  if [ "$errCode" != "200" -a "$errCode" != "201" ]
  then
    echo "ERROR"
    grep -v ERRORCODE /tmp/$$.tmp
    rm -f /tmp/$$.tmp
    die "Unable to load the file (http Error : $errCode)"
  else
    echo "Ok"
  fi
  rm -f /tmp/$$.tmp
  
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
#    Run a shell script
# 

runShell()
{
  outputFile=/tmp/$(basename $fullName .sh)_$(hostname -s)_$(date +%Y%MD_%h%m%d)_$f.txt
  scriptFile=/tmp/$$.sh.tmp
  curl -sL $fullName > $scriptFile
  chmod 700 $scriptFile
  $scriptFile $scriptParameters | tee $outputFile
  rm -f $scriptFile
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
#     RUn a SQL script (via SQLPlus)
#
runSQL()
{

  
  #
  #    Try to get DB and PDB names for the filename, if not possible, generate
  # a name at the shell level (ie: Running against ASM or e non mounted DB
  #
  f=$(sqlplus -s / as sysdba <<%%
  set feed off heading off pages 0 feedback off
  whenever sqlerror exit failure
  alter session set container=$pdbName ;
  select to_char(sysdate,'yyyymmdd_hh24miss') || '_' || lower(d.name) || '_' 
                        || replace(sys_context('USERENV','CON_NAME'),'$','_') 
  from dual,v\$database d ;
%%
) || f=$(date +%Y%m%d_%H%M%S)_${ORACLE_SID}

  outputFile=/tmp/$(basename $fullName .sql)_$(hostname -s)_$f.$outputType
  spoolOnCommand="spool $outputFile"
  spoolOffCommand="spool off"
  
  if [ "$pdbName" != "" ]
  then
    #
    #    If PDB mane is specified, we will change container
    #
    setContainerCommand="alter session set container=$pdbName ;"
  fi

  if [ "$outputType" = "html" ]
  then
    termoutCommand="set term off"
    sqlplusFormatCommand="set markup HTML ON 
  set feed off"
  fi
  
  #
  #       Generate a temporary script that will
  #  - put the exception handlers
  #  - change container
  #  - set the 9 standards parameters of SQL*Plus, this allows default parameter values
  #  - run the normal script with its parameters
  #
  #
  tmpSQLScript=/tmp/$$.tmp.sql
  echo "
  whenever sqlerror exit failure
  whenever oserror exit failure
  set feedback off
  
  $setContainerCommand
  
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


  define output_format="$outputType"

  $termoutCommand
  $sqlplusFormatCommand
  $spoolOnCommand
  set feedback 10
  $(curl -sL $fullName)
  $spoolOffCommand
  exit
  " > $tmpSQLScript
 
  #
  #   Run the script
  # 
  echo
  echo "Running the script : $fullName"
  echo "=================="
  echo
  sqlplus -s / as sysdba @$tmpSQLScript $scriptParameters || { rm -f $tmpSQLScript ; die "Error executing the script" ; }
  rm -f $tmpSQLScript

}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SCRIPT=runSQL.sh

repositoriesList="SQLTools ASMTools CNAFTools"       # List of common repositories (for those repos, the file name is sufficient to run a file
outputType=txt                                       # Default output
screenOutputOnly=N                                   # Controls the sending of the output
toShift=0                                            # Number of parameters to shift to eliminate the options and keep scripts parameters
getScriptOnly=N                                      # Get the script to a local file
uploadScriptOnly=N                                   # Upload to gitHub
while getopts "d:p:Higl?" opt
do
  case $opt in
    d) dbUniqueName=$OPTARG ; toShift=$(($toShift + 2)) ;;      # Name of the database (in oratab or $HOME/.env
    p) pdbName=$OPTARG      ; toShift=$(($toShift + 2)) ;;      # Name of the PDB
    H) outputType=html      ; toShift=$(($toShift + 1)) ;;      # Switch to HTML output (valid only for SQL)
    i) screenOutputOnly=Y   ; toShift=$(($toShift + 1)) ;;      # Avoid sending files to OS
    g) getScriptOnly=Y      ; toShift=$(($toShift + 1)) ;;      # Get the script locally
    l) uploadScriptOnly=Y   ; toShift=$(($toShift + 1)) ;;      # Send the script to gitHub   
    ?|h) shift ; usage ;;
  esac
done
shift $toShift


gitHub=https://raw.githubusercontent.com/$gitHubUser  # gitHub URL 

[ "$1" = "" ] && die "No script or script code to run"

if  [ "$uploadScriptOnly" = "Y" ]
then
  #
  #    Upload to gitHub and exit
  #
  [  -f "$1" ] || die "Upload : file: $1 non-existent"
  [  "$2" != "" ] || die "Upload : Repository name needed"
  [  "$gitHubToken" != "" ] || die "Upload : gitHubToken Required"
  uploadToGitHub $1 $2 $gitHubToken
  exit 0
fi

echo
echo "Identifying file to run ($1)"
echo "======================="
extraParameters=""
if [ -f $1 ]
then
  echo "  - Local file "
  fullName="file://$(readlink -f $1)"
  scriptExists $fullName || die "Unable to access $fullName"
  [ "$1" = "sendBucket.sh" ] && extraParameters="-b $bucketName"
elif [ "$1" = "help.sh" ]
then
  echo "  - Help"
  fullName="$gitHub/main/main/$1"
elif [ "$1" = "sendBucket.sh" ]
then
  echo "  - sendBucket.sh (remote)"
  fullName="$gitHub/main/main/$1"
  extraParameters="-b $bucketName"
elif [ "$(echo ${1^^} | cut -c 1-4)" = "HTTP" ]
then
  echo "  - Full gitHub Path"
  fullName=$1
  scriptExists $fullName || die "Unable to access $fullName"
elif [ "$(echo $1 | grep "/")" != "" ]
then
  nbSlash=$(echo -n $1 | sed -e "s;[^/];;g" | wc -c)
  echo "  - repo/file or repo/branch/file ($nbSlash /)"
  if [ $nbSlash -eq 1 ]
  then
    fullName=$gitHub/$(dirname $1)/main/$(basename $1)
  else
    fullName=$gitHub/$1
  fi
  scriptExists $fullName || die "Unable to access $fullName"
else
  echo "  - Filename only"
  found=N
  for r in $repositoriesList
  do
    echo "    - Searching $1 in $r"
    fullName=$gitHub/$r/main/$1
    scriptExists $fullName && { found=Y ; break ; }
  done
  [ "$found" = "N" ] && die "Script $1 not found in specified repositories" 
fi

if  [ "$getScriptOnly" = "Y" ]
then
  #
  #      Download the script and exit
  #
  curl -fsLO $fullName >/dev/null
  exit 0
fi

#
#      Here, we have a script to run
#

shift

#
#     Build parameter strings and protect parameters to be able to
# pass empty or multi-word parameters
#
scriptParameters="$extraParameters"
for p in "$@"
do
  if [ "$(echo $p | wc -w)" = "1" ]
  then
    scriptParameters="$scriptParameters $p"
  else
    scriptParameters="$scriptParameters \"$p\""
  fi
done

envOk=N
echo
echo "Set the environment"
echo "==================="
if  [ -f /etc/oratab ]
then
  #
  #    Check if the DB is in oratab
  #
  if [ "$(grep "^${dbUniqueName}:" /etc/oratab)" != "" ]
  then
    echo "    - $dbUniqueName found in oratab, set environment..."
    . oraenv  <<< $dbUniqueName >/dev/null
    if [ "$(echo ${ORACLE_SID^^} | cut -c 1-4)" != "+ASM" ]
    then
      #
      #     Reposition ORACLE_SID (for RAC)
      #
      ORACLE_UNQNAME=$ORACLE_SID
      ORACLE_SID=$(srvctl status database -d $ORACLE_UNQNAME | \
                       grep -i $(hostname -s) |  cut -f2 -d " ")
    fi
    envOk=Y
  fi
fi
if [ "$envOk" = "N" -a -f "$HOME/$dbUniqueName.env" ]
then
  #
  #    If setup not possible with ORATAB, try to use de $HOME env file.
  #
  echo "    - Env file found "
  . $HOME/$dbUniqueName.env
  envOk=Y
fi
  
if [ "$(echo ${ORACLE_SID^^} | cut -c 1-4)" = "+ASM" ]
then
  #
  #     If DB is ASM, remove the PDB Name, leave the line as-is
  #  otherwise getMain.sh will modify it
  #
  : ; pdbName="" # Do not change this line, otherwise, it is changed by getMain.sh
fi
  
[ "$envOk" = "N" ] && die "Unable to set environment for $dbUniqueName"


#
#      Call the run routine depending on the script's extension
#
ext=$(echo $fullName | sed -e "s;.*\.\([^\.]*\);\1;" | tr [a-z] [A-Z])
case $ext in
  SQL) runSQL ;;
  SH) runShell ;;
  *) die "Script Type ($ext) unknown" ;;
esac


#
#     Send the output to object storage if possible.
#
echo
if [    "$screenOutputOnly" = "N"               -a "$bucketName" != "" \
     -a "$(basename $fullName)" != "help.sh"   -a "$DO_NOT_SEND_OUTPUT" != "Y" \
     -a "$(basename $fullName)" != "sendBucket.sh" ]
then
  echo "Send Output (you can export DO_NOT_SEND_OUTPUT=Y to never send output)"
  echo "==========="
  echo "    - Sending $outputFile to Object Storage"
  echo
  curl -T $outputFile $bucketName
fi

rm -f $outputFile

