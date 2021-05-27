#!/bin/bash

# ================== Start generic Variables (do not remove or change this line)==================
bucketName=
# ================== End generic Variables (do not remove or change this line) ==================
usage() {
 echo "Usage :
 $SCRIPT [-?] files
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

toShift=0
while getopts "h?" opt
do
  case $opt in
    ?|h) shift ; usage ;;
  esac
done
shift $toShift


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
    fi
    rm -f /tmp/$$.tmp
  else
    echo "File not found"
  fi
done
