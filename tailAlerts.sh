usage()
{
  echo "Usage :

  $(basename $0) -d DBNAME

  "
  exit 1
}
die()
{
  echo "

  ERROR :
    $*
  "
  exit 1
}
cleanup()
{
  echo "
  Kill bacground processes
  Current process :$$
  "
  
  for p in $(ps -fu oracle | grep $$ | grep -v "oracle *$$" | awk '{print $2}')
  do
    echo "kill $p"
    kill -9 $p > /dev/null 2>&1
  done
}
[ "$1" = "" ] && usage

DB=$2

[ ! -f $HOME/$DB.env ] && die "$DB.env does not exists"


currentHost=$(hostname -s)
currentHostNum=$(echo $currentHost | sed -e "s;^\(.*\)\(.\)$;\2;")

. oraenv <<< +ASM${currentHostNum} > /dev/null || die "Unable to set +ASM${currentHostNum} environment"

GH=$ORACLE_HOME

. $HOME/$DB.env || die "Unable to set $DB environment"

trap cleanup 2 3
SSH_PIDS=""
for n in $(olsnodes)
do
  [ "$n" = "$currentHost" ] && continue
  hostNum=$(echo $n | sed -e "s;^\(.*\)\(.\)$;\2;")
  i=$(($hostNum - 1))
  i=$(($i * 10))
  indent=$(printf "${n} %${i}.${i}s > " ". . . . . . . . . . . . . . . . . . . . . . . . . . .")
  echo "$indent"
  ssh $n tail -f /u02/app/oracle/diag/rdbms/${ORACLE_UNQNAME,,}/$DB$hostNum/trace/alert_$DB$hostNum.log | sed -e "s;^;$indent;"  &
done
n=$currentHost
hostNum=$currentHostNum
i=$(($hostNum - 1))
i=$(($i * 10))
indent=$(printf "${n} %${i}.${i}s > " ". . . . . . . . . . . . . . . . . . . . . . . . . . .")
tail -f /u02/app/oracle/diag/rdbms/${ORACLE_UNQNAME,,}/$DB$hostNum/trace/alert_$DB$hostNum.log | sed -e "s;^;$indent;"

