#!/bin/bash
############################################################################################################################################################
#  This script will be used to add new nodes of any type to a cluster.
#
#Services

#A Hadoop cluster contains of multiple services that individually have either master, slave or client components. Below you will find a list of all currently supported components as part of a HDP stack divided in master, slave, or client groups. The cardinality notates the number of components that can exist at the same time in one cluster.

#Master Services

#Name				Ambari Component Name		Service		Cardinality
#NameNode			NAMENODE			HDFS		1-2
#Secondary NameNode		SECONDARY_NAMENODE		HDFS		1
#ResourceManger			RESOURCEMANAGER			YARN		1-2
#Application Timeline Server	APP_TIMELINE_SERVER		YARN		1
#HistoryServer			HISTORYSERVER			MAPREDUCE2	1
#Hive Metastore			HIVE_METASTORE			HIVE		1-2
#HiveServer2			HIVE_SERVER			HIVE		1-2
#WebHcat Server			WEBHCAT_SERVER			HIVE		1
#HBase Master			HBASE_MASTER			HBASE		1+
#Spark Job History Server	SPARK_JOBHISTORYSERVER		SPARK		1
#Nimbus Server			NIMBUS				STORM		1
#Storm REST Server		STORM_REST_API			STORM		1
#Storm UI			STORM_UI_SERVER			STORM		1
#DRPC Server			DRPC_SERVER			STORM		1
#Falcon Server			FALCON_SERVER			FALCON		1
#Zookeeper			ZOOKEEPER_SERVER		ZOOKEEPER	1+ (odd #)
#Kafka Broker			KAFKA_BROKER			KAFKA		1+
#Knox Gateway			KNOX_GATEWAY			KNOX		1+
#Ranger Admin Server		RANGER_ADMIN			RANGER		1-3
#Ranger User Sync		RANGER_USERSYNC			RANGER		1
#Ranger Key Management Server	RANGER_KMS_SERVER		RANGER_KMS	1+
#Oozie Server			OOZIE_SERVER			OOZIE		1
#Ganglia Server			GANGLIA_SERVER			GANGLIA		1
#Nagios Server			NAGIOS_SERVER			NAGIOS		1
#Ambari Metrics Service		METRICS_MONITOR		AMS		1
#Zeppelin Server		ZEPPELIN_MASTER			SPARK / HIVE	1


#Slave Services

#Name				Ambari Component Name		Service		Cardinality
#DataNode			DATANODE			HDFS		1+
#Journale Nodes for NameNode HA	JOURNALNODE			HDFS		0+ (odd #)
#Zookeeper Failover Service	ZKFC				HDFS		0+
#Secondary NameNode		NFS_GATEWAY			HDFS		0+
#Node Manager			NODEMANAGER			YARN		1+
#HBase RegionServer		HBASE_REGIONSERVER		HBASE		1+
#Phoneix Query Server		PHOENIX_QUERY_SERVER		HBASE		0+
#Storm Supervisor		SUPERVISOR			STORM		1+
#Ganglia Metrics Collector	GANGLIA_MONITOR			GANGLIA		ALL
#Ambari Metrics Collector	METRICS_MONITOR			AMS		ALL


#Clients

#Name				Ambari Component Name		Service		Cardinality
#HDFS Client			HDFS_CLIENT			HDFS		1+
#YARN Client			YARN_CLIENT			YARN		1+
#MapReduce Client		MAPREDUCE2_CLIENT		MAPREDUCE2	1+
#Spark Client			SPARK_CLIENT			SPARK		1+
#Falcon Client			FALCON_CLIENT			FALCON		1+
#HBase Client			HBASE_CLIENT			HBASE		1+
#Hive Client			HIVE_CLIENT			HIVE		1+
#HCat Client			HCAT				HIVE		1+
#Mahout Client			MAHOUT				MAHOUT		0+
#Oozie Client			OOZIE_CLIENT			OOZIE		1+
#Sqoop Client			SQOOP				SQOOP		1+
#Zookeeper Client		ZOOKEEPER_CLIENT		ZOOKEEPER	1+
nodetype="NODEMANAGER"
hdpversion=$(cat configs/config.yml | grep hdpversion | awk '{print $2}')
ambariadmin=$(cat configs/config.yml | grep ambari_user | awk '{print $2}')
ambaripass=$(cat configs/config.yml | grep ambari_password | awk '{print $2}')
ambariaddress=$(cat configs/config.yml | grep ambari_address | awk '{print $2}')
clustername=$(cat configs/config.yml | grep clustername | awk '{print $2}')

mkdir $PWD/output

if [ "x$ambariaddress" = "x" ]
 then 
   printf "Please provide the ambari local address in the config.yml file.\n"
   exit
fi

if [ "x$clustername" = "x" ]
 then
   printf "Please provide the cluster's name in the config.yml file.\n"
   exit
fi

if [ "x$1" = "x" ]
 then
   printf "Please provide the file with a list of hostnames.\n"
   exit
 else
   hostnodes="$1"
fi

if [ "x$2" = "x" ]
 then
   printf "Please provide the service component to install on the given set of hosts.\n"
   head -n 69 createclusternodes.sh
   exit
 else
   servicecomponent=$(echo $2 | tr '[:lower:]' '[:upper:]')
   if [ "$servicecomponent" = "DATANODE" ]
    then
      nodetype="MASTER"
   fi
fi

printf "Setting up service: $servicecomponent."

file='/opt/sbin/scp.sh'

if [ -f $file ]
then
   SSH='/opt/sbin/ssh.sh'
   SCP='/opt/sbin/scp.sh'
else
   SSH='ssh'
   SCP='scp'
fi


if [ "x$3" != "x" ]
 then
   numberofinstances=$3
   printf "\nCalling createbigdatanodes.sh script to create $3 instances.\n"
   ./createbigdatanodes.sh $3 "$clustername" "$nodetype"
   printf "\nWaiting for agents to register.\n"
   sleep 15
fi


printf "Waiting for servers to come online."
cat $PWD/output/privateIPs | while read server ; do
 succeeded=$(nc -zv $server 22 | grep 'succeeded')
 printf "Waiting for server: $server to come online.\n" 
 printf "Current Status = $succeeded\nWaiting."
 while [ "x$succeeded" = x ]
 do
   printf "."
   sleep 5
   succeeded=$(nc -zv $server 22 | grep 'succeeded')
 done
 printf "\n"
done


#################################################################################################################################
#  Update hosts file with master hosts
printf "Uploading hosts file.\n"
$SSH $ambariaddress 'sudo cp /etc/hosts ~/hosts'
$SSH $ambariaddress 'sudo chmod 777 ~/hosts'

$SCP $ambariaddress:~/hosts $PWD/output/
cat $PWD/output/privateIPs | grep "10." | while read server ; do $SCP $PWD/output/hosts $server:~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server  'sudo cp -f ~/hosts /etc/hosts'</dev/null ; done

########################################################################################################################################
# Update host.allow for new server

sed -e "s/10.2.150.122/$ambariaddress/g" $PWD/templates/hosts.allow.template > $PWD/output/hosts.allow

printf "Hostname file outputted to hostnames.\n Copy hosts.allow to all new hosts for access from ambari.\n"

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/output/hosts.allow "$server":~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/hosts.allow /etc/hosts.allow'</dev/null ; done



#################################################################################################################################
# This will add the requested service to the nodes and join them to the cluster.  The metrics monitor will automatically be
# included on all nodes.
# Get ambari hostname
printf "Updating ambari-agent.ini.\n"
masternode=$($SSH $ambariaddress 'hostname'</dev/null)
if [ "$hdpversion" = "hdp25" ]
then
 sed -e  "s/hostname=.*/hostname=$masternode/g" $PWD/templates/ambari-agent25.template > $PWD/output/ambari-agent.ini
else
 sed -e  "s/hostname=.*/hostname=$masternode/g" $PWD/templates/ambari-agent24.template > $PWD/output/ambari-agent.ini
fi

 cat $PWD/output/privateIPs | grep "10." | while read server ; do $SCP $PWD/output/ambari-agent.ini $server:~/</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/ambari-agent.ini /etc/ambari-agent/conf/'</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server  'sudo ambari-agent restart'</dev/null ; done



#################################################################################################################################
#  Build a list of hostnames
printf "\nCreating hostnames file.\n"

cat $PWD/output/privateIPs | while read server ; do $SSH $server 'hostname'</dev/null ; done > $PWD/output/hostnames
#cat $PWD/output/hostnames.tmp | awk '{print $1".us-west-2.compute.internal"}' > $PWD/output/hostnames
#rm -f $PWD/output/hostnames.tmp


#################################################################################################################################
#  Deploy specified service
printf "\nAmbari Address: $ambariaddress.\n"
printf "Cluster Name:   $clustername\n"
printf "Service to install: $servicecomponent\n"
printf "\nAdding services $servicecomponent to nodes..."
printf "Hosts:\n"
cat $PWD/output/hostnames
printf "\n"


cat output/hostnames | while read host ; do
 curl --user "$ambariadmin":"$ambaripass" -i -X POST http://$ambariaddress:8080/api/v1/clusters/"$clustername"/hosts/"$host"
 curl -u "$ambariadmin":"$ambaripass" -i -H 'X-Requested-By: ambari' -X POST -d '{"host_components" : [{"HostRoles":{"component_name":"'"$servicecomponent"'"}}] }' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts?Hosts/host_name="$host"
 curl --user "$ambariadmin":"$ambaripass" -i -X PUT -d '{"HostRoles": {"state": "INSTALLED"}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/"$servicecomponent"
 curl -u "$ambariadmin":"$ambaripass" -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Start '"$servicecomponent"'","query":"HostRoles/component_name.in('"$servicecomponent"')"}, "Body":{"HostRoles": {"state": "STARTED"}}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/"$servicecomponent"
 curl -u "$ambariadmin":"$ambaripass" -i -H 'X-Requested-By: ambari' -X POST -d '{"host_components" : [{"HostRoles":{"component_name":"METRICS_MONITOR"}}] }' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts?Hosts/host_name="$host"
 curl --user "$ambariadmin":"$ambaripass" -i -X PUT -d '{"HostRoles": {"state": "INSTALLED"}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/METRICS_MONITOR
 curl -u "$ambariadmin":"$ambaripass" -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Start METRICS_MONITOR","query":"HostRoles/component_name.in('METRICS_MONITOR')"}, "Body":{"HostRoles": {"state": "STARTED"}}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/METRICS_MONITOR
done


#################################################################################################################################
# Add ambari-nanny script and cron to run it.  This script will keep services up.
$PWD/deploy_nanny.sh

printf "\nNodes joined to cluster: \n"
cat $PWD/output/privateIPs
