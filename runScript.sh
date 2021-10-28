#!/bin/bash

# ================== Start generic Variables (do not remove or change this line)==================
dbUniqueName=
pdbName=
bucketName=
gitHubToken=
gitHubUser=
# ================== End generic Variables (do not remove or change this line) ==================

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
decryptToken()
{
    v=$(echo $1 | sed -e "s;@@BASE64TOKEN@@;;")
    echo -e "$v"| base64 -d | gpg --batch --passphrase "$2" -d 2>/dev/null
}
encryptToken()
{
      echo "@@BASE64TOKEN@@$(echo "$gitHubToken" | gpg --batch --passphrase "$2" -c | base64 | tr '\n' ' ' | sed -e "s; ;;g")"
}
secureToken()
{
  local rep
  if [ "$gitHubToken" = "" ]
  then
    return 1
  elif [ "$(echo $gitHubToken | cut -c 1-4)" = "ghp_" ]
  then
    echo 
    echo
    read -p "Your token is in clear text, do you want to encrypt it with a password? [Y/n] "  rep
    [ "$rep" = "" ] && rep=Y
    if [ "${rep^^}" = "Y" ]
    then
      echo "

      Your token will be encrypted using a personal password 

      "
      read -s -p "Please enter a password to encrypt the key : " pass1
      echo
      echo
      read -s -p "             Enter the same password again : " pass2 
      echo
      echo
      [ "$pass1" != "$pass2" ] && die "Passwords don't match"
      encryptedToken=$(encryptToken "$gitHubToken" "$pass1")
      #[ "$(echo $encryptedToken | grep "BEGIN PGP MESSAGE")" = "" ] && die "Token has not been encrypted" 
      [ "$(echo $encryptedToken | grep "@@BASE64TOKEN@@")" = "" ] && die "Token has not been encrypted" 
      echo "#"
      echo "# ============================================================================"
      echo "#"
      echo "#   To replace the unencrypted token by the encrypted one, simply copy/paste"
      echo "# the following lines in the terminal "
      echo "#"
      echo "# ============================================================================"
      echo "#"
      echo
      echo "sed -i \"s;^ *gitHubToken=.*$;gitHubToken=\\\"\\"
      echo "$(echo $encryptedToken|fold -c20 | sed -e "s;$;\\\\;")"
      echo "\\\";\" $0"
      echo
      echo "# ============================================================================"
      echo "#"
    else
      return 2
    fi
  elif [ "$(echo $gitHubToken | grep "@@BASE64TOKEN@@")" != "" ]
  then
    return 3
  fi
}
usage() {
 echo "Usage :
 $SCRIPT [-?] [-d dbName] [-p pdbName] [-H] [-i] [-g] [-l] {scriptName [scriptParams]}
   -?           : Help
   -H           : html output
   -i           : screen output only
   -g           : get script
   -l           : Upload script to gitHub
   -s           : Prints nothing but the result (and errors)
   -o           : Output prefix
   -O           : Output full name
   -n           : Do not generate Pre-authenticated requesl fo the output
   -B           : Launch the script in batch (nohup)
   --           : Remaining arguments are arguments to pass as is to the called script
   scriptName   : Single file name / partial path / fullPath 
   scriptParams : Parameters of the script (try HELP)

   Download a script from gitHub and run it under sqlplus or shell
   
   Note : for shell scripts with '-' options that may interfer with this script, use
   -- before arguments.
   
   $SCRIPT [$SCRIPT's arguments] test.sh -- [test.sh's arguments]
   
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

  if [ "$gitHubTokenState" = "ENCRYPTED" ]
  then
    read -s -p "Enter the password for the token : " pass
    echo
    : ; gitHubToken=$(decryptToken "$gitHubToken" $pass) || die "Unable to decrypt Token"
  fi
  [ "$(echo $gitHubToken| cut -c1-4)" != "ghp_" ] && die "Invalid gitHub Token ($gitHubToken)"
  [ "$silent" = "Y" ] || echo "Send file $f to gitHub"
  if scriptExists $gitFile
  then
    #
    #    Get SHA of the existing file
    #
    [ "$silent" = "Y" ] || echo "  - File Exists in gitHub"
    sha=$(curl -s -X GET $apiFile | grep "sha" | cut -f2 -d: | cut -f2 -d"\"")
    sha_string=" , \"sha\" : \"$sha\""
  else
    [ "$silent" = "Y" ] || echo "  - New file in gitHub"
    sha_string=""
  fi
  #
  #  Clean-up file (avoid posting personal information or token)
  #
  [ "$silent" = "Y" ] || echo "  - Cleaning file"
  cp -p $f $f.tmp
  for var in dbUniqueName pdbName bucketName gitHubToken gitHubUser
  do
    [ "$silent" = "Y" ] || echo "    - Removing $var value"
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
  [ "$silent" = "Y" ] || echo -n "  - Sending file --> "
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
    [ "$silent" = "Y" ] || echo "Ok"
  fi
  rm -f /tmp/$$.tmp
  
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
#    Run a shell script
# 

runShell()
{
  if [ "$outputName" = "" ]
  then
    outputFile=/tmp/${outputPrefix}_$(hostname -s)_$(date +%Y%m%d_%H%M%S)_$f.txt
  else
    outputFile=/tmp/$outputName
  fi
  scriptFile=/tmp/$$.sh.tmp
  curl -sL $fullName > $scriptFile
  chmod 700 $scriptFile
  eval $scriptFile "$scriptParameters" 2>&1 | tee $outputFile
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

  if [ "$outputName" = "" ]
  then
    outputFile=/tmp/${outputPrefix}_$(hostname -s)_$f.$outputType
  else
    outputFile=/tmp/$outputName
  fi
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
  alter session set nls_numeric_characters=', ';
  
  $setContainerCommand
  
  set term off
  set feed off
  set verify off
  set tab off
  set trimspool on
  set trimout on
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
  [ "$silent" = "Y" ] || echo
  [ "$silent" = "Y" ] || echo "Running the script : $fullName"
  [ "$silent" = "Y" ] || echo "=================="
  [ "$silent" = "Y" ] || echo
  sqlplus -s / as sysdba @$tmpSQLScript $scriptParameters || { rm -f $tmpSQLScript ; die "Error executing the script" ; }
  rm -f $tmpSQLScript

}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

SCRIPT=runSQL.sh

#
#   Check if token is in clear text
#   Returns :
#           1 - No token
#           2 - Clear text Token 
#           3 - Encrypted token
secureToken
case $? in
  1) gitHubTokenState="NONE" ;;
  2) gitHubTokenState="CLEAR" ;;
  3) gitHubTokenState="ENCRYPTED" ;;
  *) die "Unable to determine token encryption state" ;;
esac

repositoriesList="SQLTools ASMTools CNAFTools"       # List of common repositories (for those repos, the file name is sufficient to run a file
outputType=txt                                       # Default output
screenOutputOnly=N                                   # Controls the sending of the output
toShift=0                                            # Number of parameters to shift to eliminate the options and keep scripts parameters
getScriptOnly=N                                      # Get the script to a local file
uploadScriptOnly=N                                   # Upload to gitHub
silent=N
BATCH_MODE=N
savedArgs="$*"
while getopts "d:p:Higslo:O:Bn-?" opt
do
  case $opt in
    d) dbUniqueName=$OPTARG ; toShift=$(($toShift + 2)) ;;      # Name of the database (in oratab or $HOME/.env
    p) pdbName=$OPTARG      ; toShift=$(($toShift + 2)) ;;      # Name of the PDB
    H) outputType=html      ; toShift=$(($toShift + 1)) ;;      # Switch to HTML output (valid only for SQL)
    i) screenOutputOnly=Y   ; toShift=$(($toShift + 1)) ;;      # Avoid sending files to OS
    g) getScriptOnly=Y      ; toShift=$(($toShift + 1)) ;;      # Get the script locally
    l) uploadScriptOnly=Y   ; toShift=$(($toShift + 1)) ;;      # Send the script to gitHub   
    o) outputPrefix=$OPTARG ; toShift=$(($toShift + 2)) ;;      # Prefix Of the output File
    O) outputName=$OPTARG   ; toShift=$(($toShift + 2)) ;;      # Name Of the output File
    s) silent=Y             ; toShift=$(($toShift + 1)) ;;      # Print nothin but the output
    n) paRequest=N          ; toShift=$(($toShift + 1)) ;;      # Do not create pre-auth request
    B) BATCH_MODE=Y         ; toShift=$(($toShift + 1)) ;;      # Launch in BATCH_MODE
    -) break                ; toShift=$(($toShift + 1)) ;;      # stop Processing arguments
    ?|h) shift ; usage ;;
  esac
done
shift $toShift


gitHub=https://raw.githubusercontent.com/$gitHubUser  # gitHub URL 

OCICLI=""
testFile="/admindb/ocicli/bin/oci" ; test -f $testFile && OCICLI=$testFile
scriptFile=$(readlink -f $0)
OCICONFIG=$(dirname $scriptFile)/.oci/config
test -f $OCICONFIG || OCICLI=""
OCI_VAR_OK=Y
export OCICLI OCICONFIG OCI_VAR_OK

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

[ "$silent" = "Y" ] || echo
[ "$silent" = "Y" ] || echo "Identifying file to run ($1)"
[ "$silent" = "Y" ] || echo "======================="
extraParameters=""
if [ -f $1 ]
then
  [ "$silent" = "Y" ] || echo "  - Local file "
  fullName="file://$(readlink -f $1)"
  scriptExists $fullName || die "Unable to access $fullName"
  [ "$1" = "sendBucket.sh" ] && extraParameters="-b $bucketName"
elif [ "$1" = "help.sh" ]
then
  [ "$silent" = "Y" ] || echo "  - Help"
  fullName="$gitHub/main/main/$1"
elif [ "$1" = "sendBucket.sh" ]
then
  [ "$silent" = "Y" ] || echo "  - sendBucket.sh (remote)"
  fullName="$gitHub/main/main/$1"
  extraParameters="-b $bucketName"
elif [ "$(echo ${1^^} | cut -c 1-4)" = "HTTP" ]
then
  [ "$silent" = "Y" ] || echo "  - Full gitHub Path"
  fullName=$1
  scriptExists $fullName || die "Unable to access $fullName"
elif [ "$(echo $1 | grep "/")" != "" ]
then
  nbSlash=$(echo -n $1 | sed -e "s;[^/];;g" | wc -c)
  [ "$silent" = "Y" ] || echo "  - repo/file or repo/branch/file ($nbSlash /)"
  if [ $nbSlash -eq 1 ]
  then
    fullName=$gitHub/$(dirname $1)/main/$(basename $1)
  else
    fullName=$gitHub/$1
  fi
  scriptExists $fullName || die "Unable to access $fullName"
else
  [ "$silent" = "Y" ] || echo "  - Filename only"
  found=N
  for r in $repositoriesList
  do
    [ "$silent" = "Y" ] || echo "    - Searching $1 in $r"
    fullName=$gitHub/$r/main/$1
    scriptExists $fullName && { found=Y ; break ; }
  done
  [ "$found" = "N" ] && die "Script $1 not found in specified repositories" 
fi
[ "$outputPrefix" = "" ] && outputPrefix=$(basename $fullName | sed -e "s;^\(.*\)\.[^\.]*$;\1;")

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
if [ "$dbUniqueName" != "" ]
then
  [ "$silent" = "Y" ] || echo
  [ "$silent" = "Y" ] || echo "Set the environment"
  [ "$silent" = "Y" ] || echo "==================="
  if  [ -f /etc/oratab ]
  then
    #
    #    Check if the DB is in oratab
    #
    if [ "$(grep "^${dbUniqueName}:" /etc/oratab)" != "" ]
    then
      [ "$silent" = "Y" ] || echo "    - $dbUniqueName found in oratab, set environment..."
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
    [ "$silent" = "Y" ] || echo "    - Env file found "
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
fi

if [ "$BATCH_MODE" = "Y" ]
then
  export TEMP_LOG=/tmp/runScript.tempLog.$$
  waitFor=30
  echo "
  +==========================================================================+
  |                                                                          |
  |   BATCH_MODE : the script will be re-launched whith the same arguments   |
  |                except -B                                                 |
  |                                                                          |
  +==========================================================================+

      - A temporary log file will be created and removed after the
        bacth execution :
          $TEMP_LOG
      - After launch, the process is monitored for $waitTime to check
        correct start

       "
  args=$(echo $savedArgs | sed -e "s;-B *;;")
  nohup $0 $args >$TEMP_LOG 2>&1 &
  pid=$!
  echo " Batch Launched ..... (pid=$pid) monitoring it for ($waitFor) secondes"
    echo -n "  $pid monitoring --> "
    i=1
    while [ $i -le $waitFor ]
    do
      sleep 1
      if ps -p $pid >/dev/null
      then
        [ $(($i % 10)) -eq 0 ] && { echo -n "+" ; } || { echo -n "." ; }
      else
         if [ -f $TEMP_LOG ]
         then
           echo "Process disapear, probable error"
           echo 
           echo "      --+--> $TEMP_LOG"
           tail -20 $TEMP_LOG | sed -e "s;^;        | ;"
           echo "        +----------------------"

           die "Batch stopped" 
         else
           echo " Terminated"
           i=$waitFor
         fi
      fi
      i=$(($i + 1))
    done  
    echo
    echo
    echo "+===========================================================================+"
    echo "| Batch seem to have been launched sucessfully                              |"
    echo "+===========================================================================+"
    exit
  exit
fi
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
[ "$silent" = "Y" ] || echo
if [    "$screenOutputOnly" = "N"                  -a "$bucketName" != "" \
     -a "$(basename $fullName)" != "help.sh"       -a "$DO_NOT_SEND_OUTPUT" != "Y" \
     -a "$(basename $fullName)" != "sendBucket.sh" -a "$(basename $fullName)" != "getPass.sh" ]
then
  [ "$silent" = "Y" ] || echo "Send Output (you can export DO_NOT_SEND_OUTPUT=Y to never send output)"
  [ "$silent" = "Y" ] || echo "==========="
  [ "$silent" = "Y" ] || echo "    - Sending $outputFile to Object Storage"
  curl -T $outputFile $bucketName
  f=$(basename $outputFile)
  if [ "$paRequest" != "N" ]
  then
    if [ "$OCICLI" != "" ]
    then
      echo "    - Generating Pre-authenticated Request ...."
      expireDate=$(date -d "Tomorrow" "+%Y-%m-%dT%H:%M:%SZ")
      result=$($OCICLI os preauth-request create --config-file $OCICONFIG --access-type ObjectRead --bucket-name MBO --object-name $f --time-expires $expireDate --name $f)
      if [ $? -eq 0 ]
      then
        accessURI=$(echo "$result" | grep access-uri | cut -f2 -d":"| cut -f2 -d "\"")
        echo "    - File can be downloaded with "
        echo
        echo "curl -O https://objectstorage.eu-frankfurt-1.oraclecloud.com$accessURI"  | fold -w 90 | sed -e "s;$;\\\\;" | sed -e "$ s;\\\\$;;"
        echo
      else
        echo "    - Access URI not generated"
      fi
    else
      die "Unable to find ocicli or config file ($OCICONFIG)"
    fi
  fi  
fi

[ "$silent" = "Y" ] || echo "
============================================================================
Script was run in the following environment :
   Host           : $(hostname -f)
   DB Unique Name : $dbUniqueName
   PDB Name       : $pdbName
============================================================================
"

rm -f $outputFile

# Remove temp log (when process is re-launched in Nohup)
if [ "$TEMP_LOG" != "" ]
then
  rm -f $TEMP_LOG
fi
