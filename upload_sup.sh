#!/bin/bash

if [ -z $2 ]; then 
echo "Usage : 
  upload_sup.sh file SRNumber"
exit 1
fi

curl -v -T $1 -u michel.bottione@oracle.com https://transport.oracle.com/upload/issue/$2/
