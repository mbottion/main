#!/bin/bash
secs2HMS()
{
  local secs=$1
  local h=$(( $secs / 3600))
  local r=$(( $secs % 3600 ))
  local m=$(( $r / 60))
  local s=$(( $r % 60))
  printf "%4d:%02d:%02d" $h $m $s
}
startRun()
{
  START_INTERM_EPOCH=$(date +%s)
  START_INTERM_FMT=$(date +"%d/%m/%Y %H:%M:%S")
  echo   "========================================================================================"
  echo   " Execution start"
  echo   "========================================================================================"
  echo   "  - $1"
  echo   "  - Started at     : $START_INTERM_FMT"
  echo   "========================================================================================"
  echo
}
endRun()
{
  END_INTERM_EPOCH=$(date +%s)
  END_INTERM_FMT=$(date +"%d/%m/%Y %H:%M:%S")
  all_secs2=$(expr $END_INTERM_EPOCH - $START_INTERM_EPOCH)
  mins2=$(expr $all_secs2 / 60)
  secs2=$(expr $all_secs2 % 60 | awk '{printf("%02d",$0)}')
  echo
  echo   "========================================================================================"
  echo   "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - "
  echo   "  - Ended at      : $END_INTERM_FMT"
  echo   "  - Duration      : ${mins2}:${secs2}"
  echo   "========================================================================================"
  echo   "Script LOG in : $LOG_FILE"
  echo   "========================================================================================"
  if [ "$CMD_FILE" != "" ]
  then
    echo   "Commands Logged to : $CMD_FILE"
    echo   "========================================================================================"
  fi
}
usage() {
 echo "Usage :
 $SCRIPT [-?] files
   -b bucket    : use another bucket
   -?           : Help
   -t           : Time (days) to keep the PAR
   -l           : List bucket content (need a read PAR on the bucket)
   -g file      : get a file (need a read PAR on the bucket)
   -n           : Do not generate a PAR for uploaded files
   -p           : Generate a PAR for uploaded files
   Send files o the exchange bucket
  "
  exit
}
die()
{
  [ "$START_INTERM_EPOCH" != "" ] && endRun
  echo "
ERROR :
  $*"

  rm -f $PID_FILE

  exit 1
}
killSplit()
{
  #
  #        Kill background processes when interrupt or error
  #
  echo
  echo "====================================================="
  echo "  - CTRL-C received in process $currentPROCESS"
  echo "  - Kill $splitPID"
  kill -9 $splitPID
  ps -ef | grep split | grep split.$currentPROCESS | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
  echo "  - Kill curls"
  ps -ef | grep curl | grep split.$currentPROCESS | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
  echo "  - Removing *.split.$currentPROCESS files"
  rm -f *.split.$currentPROCESS
  rm -f *.split.log.$currentPROCESS
  rm -f *.splitKO.$currentPROCESS
  echo "  - Removing *.split.$currentPROCESS files"
  rm -f *.split.$currentPROCESS.errLoad
  echo "  - Exiting"
  if [ "$accessURI" != "" ]
  then
    echo "  - Removing MULTIPART upload"
    curl -X DELETE $accessURI
  fi
  echo "====================================================="
  exit 1
}
uploadFile()
{
  #
  #      Launch the curl command to upload a file part. If more than MAX_CURL curls 
  #  are running, wait until some finishes
  #
  local nbCURL=$(ps -ef | grep curl | grep -v grep | wc -l)
  [ $nbCURL -ge $MAX_CURL ] && echo "  - $(basename $1) : Upload Waiting - too much curls"
  while [ $nbCURL -ge $MAX_CURL ]
  do
    sleep 3
    nbCURL=$(ps -ef | grep curl | grep -v grep | wc -l)
  done
  local indent="    "
  local n=1
  while [ $n -le $nbCURL ]
  do
    indent="$indent  "
    n=$(($n + 1))
  done
  indent="${indent}  - $(basename $1) : "
  local start_upload_part=$(date +%s)
  echo "${indent}Upload start(background) $s"
  curl -w "Status:%{http_code}" -v -X PUT --data-binary @$1 ${accessURI}$2 >$1.errLoad 2>&1
  local end_upload_part=$(date +%s)
  local secs=$(($end_upload_part - $start_upload_part))
  if grep "Status:200" $1.errLoad >/dev/null
  then
    echo "${indent}sucessfully uploaded in $(secs2HMS $secs)"
    rm -f $1.errLoad
  fi
  echo "${indent}Remove $1"
  rm -f $1
}

splitFile()
{
  #
  #     Split the file in $SPLIT_SIZE parts in backgroun. If split has an error, kills everything
  #
  echo "  - Splitting file in $MAX_SIZE BYTES parts (background)"
  split -b $SPLIT_SIZE  --suffix-length=5 --additional-suffix=.split.$currentPROCESS --numeric-suffixes=1 $1 >$1.split.log.$currentPROCESS 2>&1
  if [ $? -ne 0 ]
  then
    echo
    echo "Error durung split, aborting"
    echo
    cat $1.split.log.$currentPROCESS
    rm -f $1.split.log.$currentPROCESS
    touch $1.splitKO.$currentPROCESS
    killSplit
  else
    echo "  - File sucessfully splitted"
  fi
}
multiPartUpload()
{
  #
  #     Manages the MULTIPART upload process. since split is running in background, while
  # split is running, we launch part N only when file N+1 exists.
  #
  #     After split terminates, the remainint parts are uploaded.
  #
  export currentPROCESS=$$
  local start_multipart=$(date +%s)
  echo "Multi part upload (PID=$currentPROCESS)" 
  #
  #    Generate the multipart upload URI
  #
  accessURI=$(curl -s -X PUT -H "opc-multipart:true" ${bucketName}${1})
  if ! echo "$accessURI" | grep "accessUri" >/dev/null
  then
    die "Error getting the MULTIPART acces URI ($accessURI)"
  fi
  accessURI=$(echo $accessURI | sed -e "s;^.*/u/$1;/u/$1;" -e "s;\"};;")
  export accessURI=$(echo $bucketName | sed -e "s;/o/;;")${accessURI}
  echo "  - Create multipart UPLOAD"
  echo "    $accessURI"
  part=1
  #
  #    Launch file split in background (first part is '1'
  #
  splitFile $1 &
  splitPID=$!
  echo "    PID=$splitPID"
  i=1
  while ps -p $splitPID >/dev/null
  do
    n1=$(printf "%05d" $i)
    n2=$(printf "%05d" $(($i + 1)))
    #
    #    SInce split is running wait for the next file to be created before
    #  uploading
    #
    if [ -f x${n1}.split.$currentPROCESS -a -f x${n2}.split.$currentPROCESS ]
    then
      uploadFile x${n1}.split.$currentPROCESS $i &
      i=$(($i + 1))
      continue
    fi
    # echo "    - Wait for file"
    sleep 1
  done
  #
  #    Split is terminated, upload the remaining files
  #
  n1=$(printf "%05d" $i)
  echo "  - Split terminated, uploading remaining files"
  while [ -f x${n1}.split.$currentPROCESS ] 
  do
    uploadFile x${n1}.split.$currentPROCESS $i &
    i=$(($i + 1)) 
    n1=$(printf "%05d" $i)
  done
  #
  #     All uploads launched, need to wait for all background processes to terminate
  #
  echo "  - All done, waiting for background processes to terminate"
  wait
  local end_multipart=$(date +%s)
  local secs=$(($end_multipart - $start_multipart))
  if [ "$(ls *.errLoad.$currentPROCESS 2>/dev/null)" != "" -o -f $1.splitKO.$currentPROCESS ]
  then
    #
    #   Each process controls its errors and removes the output if no errors are encountered
    #  if out files remain here, there were errors
    #
    echo "  - ERROR uploading some parts"
    for f in *.errLoad.$currentPROCESS
    do
      echo "  - $f"
      echo "  - ---------------------------------------------------------"
      cat $f
      rm -f $f
    done
    #
    #    DELETE the multipart request and clean the bucket
    #
    echo "  - Cancel MULTIPART upload"
    curl -X DELETE $accessURI
    status=1
  else
    #
    #    Upload OK, commit it
    #
    echo ""
    echo "  - $1 SUCCESSFULLY uploaded in $(secs2HMS $secs)"
    echo
    echo "  - Commit MULTIPART upload"
    curl -X POST $accessURI
    status=0
  fi
  rm -f $f.splitKO.$currentPROCESS
  return $status
}

listBucket()
{
  #
  #     List the bucket content, only if a bucket read PAR is available.
  #
  #
  # this hould be more simple using JQ, but thius is not commonly installed on servers
  # so, doinq it old school !!
  #
  if [ -t 1 ]
  then
    echo
    echo    "Files in the bucket"
    echo    "==================="
    echo
  fi
  i=0
  temp=$(mktemp)
  curl -s $bucketRead | sed -e "s;^.*\[;;" | tr ',' '\n' | sed -e "s;[{\"}];;g" -e "s;\];;g"> $temp
  echo >> $temp
  sed -i "/ *$^/ d" $temp
  while read line
  do
    f=$(echo $line | cut -f2 -d":")
    if [ -t 1 ] 
    then
      echo -n "  - " 
    fi
    echo -n $f
    if [ -t 1 ] 
    then
      echo -n " ($(echo $bucketRead | sed -e "s;/*$;;")/$f)" 
    fi
    echo
    i=$(($i+1))
  done < $temp
  rm -f $temp
  if [ -t 1 ]
  then
    echo
    echo "    $i files"
    echo "    NOTE : If this command is piped to something else, only file names are printed"
    echo
  fi
}
getFile()
{
  #
  #     Download a given file, only if a bucket read PAR is available.
  #
  f=$1
  echo "  - Testing file existence"
  if ! listBucket | grep "^$f" >/dev/null
  then
    die "$f does not exits in the bucket"
  fi
  echo "  - get $f"
  curl -s -o $f.tmp.$$ $(echo $bucketRead | sed -e "s;/*$;;")/$f
  [ ! -f $f.tmp.$$  ] && die "Error retrieving $f"
  if grep "{\"code\":" $f.tmp.$$ > /dev/null
  then
    cat $f.tmp.$$
    rm -f $f.tmp.$$
    die "Error downloading $f"
  else
    mode=""
    [ -f $f ] && mode=$(stat -c%a $f)
    mv $f.tmp.$$ $f
    [ "$mode" != "" ] && chmod $mode $f
  fi
}

#
#      Parameters
#
MAX_SIZE=$((1024 * 1024 * 1024 * 20))           # Beyond this size, we use multipart UPLOAD
# MAX_SIZE=0                                    # If MAX_SIZE=0, standard upload, whatever the file size is
SPLIT_SIZE=$((1024 * 1024 * 1024 * 1))          # Split chunck size
MAX_CURL=20                                     # Number of cuncurrent curls permited
genPAR=N                                        # After upload, a attempt to create a PAR is done
# PAR to write to the bucket
bucketName=
# PAR to read the bucket
bucketRead=

trap killSplit INT                              # Trap to clean background processes 

SCRIPT=$(basename $0)
PARValidity=1
ToShift=0
while getopts ":b:t:lg:h?" opt
do
  case $opt in
    b) bucketName=$OPTARG ; ToShift=$(($ToShift + 2)) ;;
    t) PARValidity=$OPTARG ; ToShift=$(($ToShift + 2)) ;;
    l) LIST_BUCKET=Y ; ToShift=$(($ToShift + 1)) ;;
    g) GET_FILE=Y ; fileToGet=$OPTARG ; ToShift=$(($ToShift + 2)) ;;
    ?|h) shift ; usage ;;
  esac
done
shift $ToShift

[ "$OCI_CONFIG_FILE" != "" ] && OCICONFIG=$OCI_CONFIG_FILE

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

if [ "$LIST_BUCKET" = "Y" ]
then
  [ "$bucketRead" = "" ] && die "List bucket requires a read PA to be defined"
  listBucket
  exit
fi
if [ "$GET_FILE" = "Y" ]
then
  [ "$bucketRead" = "" ] && die "List bucket requires a read PA to be defined"
  [ "$fileToGet" = "" ] && die "Filename needed" 
  getFile $fileToGet
  exit
fi

[ "$1" = "" ] && die "No file to send"

echo "Sending files to object Storage ($*)"
for f in $*
do
  printf "  -+--> %-50.50s : " "$f"
  if [ -f "$f" ]
  then
    echo -n "Sending ... --> "
    size=$(stat -c+%s $f)
    if [ $size -le $MAX_SIZE -o $MAX_SIZE -eq 0 ]
    then
      echo -n "Standard upload --> "
      start_standard=$(date +%s)
      curl -w "Status:%{http_code}" -v -fT $f ${bucketName} >/tmp/$$.tmp 2>&1
      if grep "Status:200" /tmp/$$.tmp >/dev/null
      then
        end_standard=$(date +%s)
        secs=$(($end_standard - $start_standard))
        echo "$(secs2HMS $secs)) : OK"
        rm -f /tmp/$$.tmp
      else
        echo "KO"
        cat /tmp/$$.tmp
        rm -f /tmp/$$.tmp
        die "Error uploading $f"
      fi
    else
      echo "  - Multipart upload"
      multiPartUpload $f  ${bucketName}
      if [ $? -ne 0 ]
      then
        die "Error uploading $f (Multipart)"
      fi
    fi
    f2=$(basename $f)
    if [ "$genPAR" != "N" ]
    then
      if [ "$OCICLI" != "" ]
      then
        echo "    - Generating Pre-authenticated Request ...."
        expireDate=$(date -d "Now + $PARValidity days" "+%Y-%m-%dT%H:%M:%SZ")
        echo "      - Expire date : $expireDate"
        #echo ${bucketName}
        #echo $OCICLI os preauth-request create --config-file $OCICONFIG --access-type ObjectRead --bucket-name MBO --object-name $f2 --time-expires $expireDate --name $f2
        result=$($OCICLI os preauth-request create --config-file $OCICONFIG --access-type ObjectRead --bucket-name MBO --object-name $f2 --time-expires $expireDate --name $f2)
        if [ $? -eq 0 ]
        then
          accessURI=$(echo "$result" | grep access-uri | cut -f2 -d":"| cut -f2 -d "\"")
          echo "    - File can be downloaded with "
          echo
          #echo "curl -O https://objectstorage.eu-frankfurt-1.oraclecloud.com$accessURI"  | fold -w 90 | sed -e "s;$;\\\\;" | sed -e "$ s;\\\\$;;"
          echo "curl -O https://objectstorage.eu-frankfurt-1.oraclecloud.com$accessURI"  
          echo
        else
          echo "    - Access URI not generated"
        fi
      else
        echo "Unable to find ocicli or config file ($OCICONFIG)"
      fi
    fi
    rm -f /tmp/$$.tmp
  else
    echo "File not found"
  fi
done
