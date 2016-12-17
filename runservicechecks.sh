#!/bin/bash
############################################################################################################################################################
#  This script will run a service check against the major services.  Currently set to run against HDFS, YARN, and MapReduce2.
#  Reads service payload from config/servicecheck_payload
if [ "x$1" = "x" ]
 then 
   printf "Please provide the ambari local address.\n"
   exit
 else
   ambariaddress=$1
fi

if [ "x$2" = "x" ]
 then
   printf "Please provide the cluster's name.\n"
   exit
 else
   clustername=$2
fi


############################################################################################################################################################
#  Call API to run service checks.
sed -e "s/<clustername>/$clustername/g" $PWD/templates/servicecheck_payload > $PWD/output/servicecheck_payload
curl -ivk -H "X-Requested-By: ambari" -u admin:admin -X POST -d @$PWD/output/servicecheck_payload http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/request_schedules
