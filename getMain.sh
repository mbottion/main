#!/bin/bash
#bash -c "set runSql ; $(curl -sL bit.ly/getMain)"
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}

setupVariable()
{
  local v=$1
  local s=$2
  local value
  local defaultValue
  if [ -f $s.old ]
  then
    value=$(sed -e "s;#.*$;;" $s.old | grep "^${v}=" | cut -f2 -d= | head -1) 
  fi
  defaultValue=$value
  case $v in
    dbUniqueName) defaultValue=${ORACLE_UNQNAME} ;;
    oracleSid)    defaultValue=${ORACLE_SID} ;;
    oracleHome)   defaultValue=${ORACLE_HOME} ;;
  esac
  if [ -z "$value" -o "$FORCE_READ" = "Y" ]
  then
    read -p "  - Enter default value for $v [$defaultValue] : " value
    [ -z $value ] && value=$defaultValue
  fi
  if [ "$(grep "^ *${v}=" $s)" = "" ]
  then
    if [ "$(grep "$START_VARS_TAG" $s)" = "" ]
    then
      sed -i "1,/^[^#]/ s/^[^#]/# ================== $START_VARS_TAG (do not remove or change this line)==================\n&/" $s
    fi
    if [ "$(grep "$END_VARS_TAG" $s)" = "" ]
    then
      sed -i "/$START_VARS_TAG/a # ================== $END_VARS_TAG (do not remove or change this line) ==================" $s
    fi
      sed -i "/$END_VARS_TAG/i ${v}=$value" $s
  else
    sed -i "s;\(^ *\)\(${v} *\)=\([^ \t]*\)\(.*$\);\1\2=$value\4;" $s
  fi
  
}
usage()
{
  echo "Usage :
  $SCRIPT [-?|-f] scriptCode
    -?         : Help
    -f         : Force variable input
    scriptCode : name of the script to get (runSQL|runShell)
    
    Get the script from gitHub and add non public variables in it"
  
  exit 
}
SCRIPT=getMain.sh
START_VARS_TAG="Start generic Variables"
END_VARS_TAG="End generic Variables"
FORCE_READ=N

[ "$1" = "-f" ] && { FORCE_READ=Y ; shift ; }
[ "$1" = "-?" ] && usage 

if [ "$1" = "" ]
then
  script_type="RUNSCRIPT"
else
  script_type=${1^^}
fi

gitHub=https://raw.githubusercontent.com/mbottion

echo "Getting Main scripts : $1"

case $script_type in
  RUNSCRIPT)
    src=runScript.sh
    repo=main
    variables="dbUniqueName pdbName bucketName gitHubToken gitHubUser"
    ;;
  SENDBUCKET)
    src=sendBucket.sh
    repo=main
    variables="bucketName"
    ;;
  *)
    die "Unknown script type ($script_type), use runScript or sendBucket"
    ;;
esac

getURL=$gitHub/$repo/main/$src

[ -f $src ] && mv $src $src.old

rm -f $src
curl -fsO $getURL  || { rm -f $src ; [ -f $src.old ] && cp -p $src.old $src ; die "Unable to get $src from gitHub" ; }

for v in $variables
do
  setupVariable $v $src
done

chmod 775 $src
rm -f $src.old
