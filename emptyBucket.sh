export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
COMPARTMENT=ocid1.compartment.oc1..aaaaaaaad3rjy2u2jsecs7npy2ib2lxmo3g6wyjlxzwjfnq6vbdabyzpfcca

oci os object list -ns cnafsi -bn MBO | jq -jr '.data[] | .name ," ",.size, "\n"' | while read file size
do
  echo -n "  - $file : "
  if [ "$1" = "-d" ]
  then
    oci os object delete -ns cnafsi -bn MBO --name $file --force
    [ $? -eq 0 ] && echo " Deleted" || echo "Error ($?)"
  else
    echo " $size (use -d to delete)"
  fi
done


