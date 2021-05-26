#!/bin/bash
die()
{
  [ "$1" != "" ] && echo -e "$SCRIPT : Error \n$*"
  exit 1
}
SCRIPT=$(basename $0)
[ "$1" = "" ] && die "Please enter the script Type [runSQL|runShell]"
echo "Getting Main scripts : $1"
