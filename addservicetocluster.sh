#!/bin/bash
#######################################################################################################################
#  This script will be used to add a new service to HDP

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

if [ "x$3" = "x" ]
 then
   printf "Please provide the service to add to cluster.\n"
   printf "Service Names:\
HDFS\
YARN\
MAPREDUCE2\
HIVE\
HBASE\
SPARK\
SPARK2\
STORM\
FALCON\
ZOOKEEPER\
KAFKA\
KNOX\
RANGER\
RANGER_KMS\
OOZIE\
GANGLIA\
NAGIOS\
AMS\
SQOOP\
MAHOUT\
HBASE"
   exit
 else
   servicename=$3
fi

#if [ "x$4" = "x" ]
# then
#   printf "Please provide a host for the service"
#   exit
# else
#   hostname=$4
#fi


#To Do find clustername

#./createbigdatanode 1 $clustername

curl -u admin:admin -i -X POST -d '{"ServiceInfo":{"service_name":"'"$servicename"'"}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/services
curl -u admin:admin -i -X PUT -d '{"ServiceInfo": {"state" : "STARTED"}}'  http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/services/"$servicename"
