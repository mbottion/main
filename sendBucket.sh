#!/bin/bash
# ================== Start generic Variables (do not remove or change this line)==================
bucketName=
# ================== End generic Variables (do not remove or change this line) ==================
usage() {
 echo "Usage :
 $SCRIPT [-?] files
   -b bucket    : use another bucket
   -?           : Help
   scriptParams : Parameters of the script (try HELP)

   Send files o the exchange bucket
  "
  exit
}
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}

SCRIPT=sendBucket.sh
while getopts ":b:h?" opt
do
  case $opt in
    b) bucketName=$OPTARG ; shift 2 ;;
    ?|h) shift ; usage ;;
  esac
done

if [ "$OCICLI"="" ]
then
  if [ -f "/admindb/ocicli/bin/oci" ]
  then
    OCICLI="/admindb/ocicli/bin/oci"
  elif [ -f "$HOME/bin/oci" ]
  then
    OCICLI="$HOME/bin/oci"
  fi
fi
if [ "$OCICONFIG" = "" ]
then
  scriptFile=$(readlink -f $0)
  if [ -f $(dirname $scriptFile)/.oci/config ]
  then
    OCICONFIG=$(dirname $scriptFile)/.oci/config
  elif [ -f "$HOME/.oci/config" ]
  then
    OCICONFIG="$HOME/.oci/config"
  fi
fi

[ "$1" = "" ] && die "No file to send"

echo "Sending files to object Storage"
for f in $*
do
  printf "  -+--> %-50.50s : " "$f"
  if [ -f "$f" ]
  then
    echo -n "Sending ... --> "
    curl -fT $f ${bucketName} >/tmp/$$.tmp 2>&1
    if [ $? -ne 0 ]
    then
      echo "ERROR"
      echo "   |"
      echo "   +---+-----------------------------------------------------"
      cat /tmp/$$.tmp | tr '\r' '\n' | sed -e "s;^;   |   |;"
      echo "   |   +-----------------------------------------------------"
      echo "   |"
    else
      echo "OK"
      f2=$(basename $f)
      if [ "$paRequest" != "N" ]
      then
        if [ "$OCICLI" != "" ]
        then
          echo "    - Generating Pre-authenticated Request ...."
          expireDate=$(date -d "Tomorrow" "+%Y-%m-%dT%H:%M:%SZ")
          result=$($OCICLI os preauth-request create --config-file $OCICONFIG --access-type ObjectRead --bucket-name MBO --object-name $f2 --time-expires $expireDate --name $f2)
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
          echo "Unable to find ocicli or config file ($OCICONFIG)"
        fi
      fi
      rm -f /tmp/$$.tmp
    fi
  else
    echo "File not found"
  fi
done
