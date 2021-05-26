#!/bin/bash
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}
SCRIPT=getMain.sh
[ "$1" = "" ] && die "$1 not understood, P lease enter the script Type [runSQL|runShell]"
echo "Getting Main scripts : $1"
