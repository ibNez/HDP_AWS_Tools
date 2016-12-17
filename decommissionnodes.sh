#!/bin/bash
ambariadmin=$(cat configs/config.yml | grep ambari_user | awk '{print $2}')
ambaripass=$(cat configs/config.yml | grep ambari_password | awk '{print $2}')
clustername=$(cat configs/config.yml | grep clustername | awk '{print $2}')
ambariaddress=$(cat configs/config.yml | grep ambari_address | awk '{print $2}')


if [ "x$ambariaddress" = "x" ]
then
  printf "Please privide the ambari server local IP to the config.yml file.\n"
  exit
fi

if [ "x$clustername" = "x" ]
then
  printf "Please privide the clustername in the config.yml file.\n"
  exit
fi

if [ "x$1" = "x" ]
then
  printf "Please privide a list of system's ips to decommision.\n"
  exit
else
  listofsystems=$1
fi

if [ "x$2" = "x" ]
then
  printf "Please privide the decommission type. (terminatenodes|terminatecluster|service|stop)\n"
  exit
else
  if [ "$2" = "service" ]
   then
    printf "Please provide the service to $2."
    exit
  else
   servicetodecommission="$3"
  fi
decommissiontype="$2"
fi

file='/opt/sbin/scp.sh'

if [ -f $file ];
then
   SSH='/opt/sbin/ssh.sh'
   SCP='/opt/sbin/scp.sh'
else
   SSH='ssh'
   SCP='scp'
fi





#############################################################################################################################################################
#  Create a list of hostnames from the IPs provided
rm $PWD/output/hostnames
printf "\nBuilding a list of hostnames from IPs.\n"
#for line in $(<$3); do echo $SSH $server 'hostname'</dev/null >> $PWD/output/hostnames ; done

cat $listofsystems | while read server ; do $SSH $server 'hostname'</dev/null >> $PWD/output/hostnames ; done


#############################################################################################################################################################
#  This Function will remove all service from a HDP node
remove_nodes_hdp () {
cat $PWD/output/hostnames | while read host ; do
  InstalledServices=$(curl --user "$ambariadmin":"$ambaripass" -i -X GET http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host" | grep component_name | awk -F'"' '{print $4}')
  printf "Services found on host $host:\n"
  echo "$InstalledServices"
  echo InstalledServices | while read service ; do
    printf "Removing service $service from host $host"
    curl -i -H "X-Requested-By: ambari" -u "$ambariadmin":"$ambaripass" -X DELETE "http://$ambariaddress:8080/api/v1/clusters/$clustername/hosts/$host/host_components/$service"
  done
  printf "Removing host($host) from cluster($clustername).\n"
  curl -i -H "X-Requested-By: ambari" -u "$ambariadmin":"$ambaripass" -X DELETE "http://$ambariaddress:8080/api/v1/clusters/$clustername/hosts/$host"
done
}

put_nodes_in_maintenancemode () {
cat $PWD/output/hostnames | while read host ; do
 curl -u "$ambariadmin":"$ambaripass" -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo":{"context":"Turn On Maintenance Mode for host","query":"Hosts/$host"},"Body":{"Hosts":{"maintenance_state":"ON"}}}' http://$ambariaddress:8080/api/v1/clusters/$clustername/hosts/$host
done
}

remove_service_from_nodes () {
  cat $PWD/output/hostnames | while read host ; do
   curl -i -H "X-Requested-By: ambari" -u "$ambariadmin":"$ambaripass" -X DELETE "http://$ambariaddress:8080/api/v1/clusters/$clustername/hosts/$host/host_components/$servicetodecommission"
  done
}

remove_monitors () {
 cat $listofsystems | while read server ; do
  $SSH $server 'sudo rsync  -avz  dl.kshwtj.com::kagent /opt/kingsoft/kagent/'</dev/null
  $SSH $server 'sudo python /opt/kingsoft/kagent/del_zbx.py'</dev/null
 done
}


terminate_nodes_aws () {
 cat $listofsystems | while read server ; do  
  instanceID=$(aws ec2 describe-instances --filters="Name=private-ip-address,Values=$server" | grep InstanceId | awk -F'"' '{print $4}')
  printf "Terminating server($server) in AWS.\n"
  aws ec2 terminate-instances --instance-ids $instanceID
 done
}

stop_nodes_aws () {
 cat $listofsystems | while read server ; do
  instanceID=$(aws ec2 describe-instances --filters="Name=private-ip-address,Values=$server" | grep InstanceId | awk -F'"' '{print $4}')
  printf "Stopping server($server) in AWS.\n"
  aws ec2 stop-instances --instance-ids $instanceID
 done
}

stop_node_services () {
#if [ $service = "NODEMANAGER" ]
#then

#fi
cat $PWD/output/hostnames | while read host ; do
 InstalledServices=$(curl --user "$ambariadmin":"$ambaripass" -i -X GET http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host" | grep component_name | awk -F'"' '{print $4}')
 echo InstalledServices | while read service ; do

#   if [ $service = "NODEMANAGER" ]
#   then
#     curl -u "$ambariadmin":"$ambaripass" -i -H 'X-Requested-By: ambari' -X POST -d '{
#   "RequestInfo":{
#      "context":"Decommission NodeManagers",
#      "command":"DECOMMISSION",
#      "parameters":{
#         "slave_type":"NODEMANAGER",
#         "excluded_hosts":"$host"
#       },
#      "operation_level":{
#         "level":"HOST_COMPONENT",
#         "cluster_name":"$clustername"
#       }
#       },
#      "Requests/resource_filters":[
#       {
#         "service_name":"YARN",
#         "component_name":"RESOURCEMANAGER"
#       }
#      ]
#     }' http://"$ambariaddress":8080/api/v1/clusters/c1/requests

#     curl -u "$ambariadmin":"$ambaripass" -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Stopping $service","query":"HostRoles/component_name.in('"$service"')"}, "Body":{"HostRoles": {"state": "DECOMMISION"}}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/$service
#     wait 20;
#   fi

   curl -u "$ambariadmin":"$ambaripass" -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo": {"context": "Stopping $service","query":"HostRoles/component_name.in('"$service"')"}, "Body":{"HostRoles": {"state": "STOPPED"}}}' http://"$ambariaddress":8080/api/v1/clusters/"$clustername"/hosts/"$host"/host_components/$service
 done
done
}

get_list_of_server () {
aws ec2 describe-instances --filters="Name=tag:cluster,Values=$clustername" | grep 'PrivateIpAddress": "10' | awk -F'"' '{print $4}' | sort -u > $PWD/output/privateIPs
}

#####################################################################################################################################################################
#  Main script

main () {
 if [ $(echo $decommissiontype | tr '[:upper:]' '[:lower:]')  = "terminatenodes" ]
  then
   put_nodes_in_maintenancemode
   stop_node_services
   remove_nodes_hdp
   remove_monitors
    ## TODO: Add a check here that the services have been stopped and removed.
   terminate_nodes_aws
 elif [ $(echo $decommissiontype | tr '[:upper:]' '[:lower:]')  = "service" ]
  then
   stop_node_services
   remove_service_from_nodes
 elif [ $(echo $decommissiontype | tr '[:upper:]' '[:lower:]')  = "stop" ]
  then
   put_nodes_in_maintenancemode
   stop_monitors
   stop_nodes_aws
 elif [ $(echo $decommissiontype | tr '[:upper:]' '[:lower:]')  = "terminatecluster" ]
  then
   get_list_of_server
   remove_monitors
   terminate_nodes_aws
 else
  exit
 fi
}

main
