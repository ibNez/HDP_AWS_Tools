#!/bin/bash

if [ "x$1" = "x" ]
then
  printf "Please privide the ambari server local IP.\n"
  exit
else
  ambariaddress="$1"
fi

if [ "x$2" = "x" ]
then
  printf "Please privide the clustername.\n"
  exit
else
  clustername=$2
fi

if [ "x$3" = "x" ]
then
  printf "Please privide a list of system's IPs to start.\n"
  exit
else
  listofsystems=$3
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
#cat $listofsystems | while read server ; do $SSH $server 'hostname'</dev/null >> $PWD/output/hostnames ; done
cat $listofsystems | while read server ; do aws ec2 describe-instances --filters="Name=private-ip-address,Values=$server" | grep PrivateDnsName | tail -n 1 | awk -F'"' '{print $4}' >> $PWD/output/hostnames ; done

#############################################################################################################################################
remove_maintenance_mode () {
cat $PWD/output/hostnames | while read host ; do
 curl -u admin:admin -H "X-Requested-By:ambari" -i -X PUT -d '{"RequestInfo":{"context":"Turn On Maintenance Mode for host","query":"Hosts/$host"},"Body":{"Hosts":{"maintenance_state":"OFF"}}}' http://$ambariaddress:8080/api/v1/clusters/$clustername/hosts/$host
done
}

start_nodes_aws () {
 cat $listofsystems | while read server ; do
  instanceID=$(aws ec2 describe-instances --filters="Name=private-ip-address,Values=$server" | grep InstanceId | awk -F'"' '{print $4}')
  printf "Starting server($server) in AWS.\n"
  aws ec2 start-instances --instance-ids $instanceID
 done
}

wait_for_servers () {
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
}

call_ambari_nanny () {
cat $PWD/output/privateIPs | while read server ; do
 $SSH $server "sudo -u tony.philip /usr/local/bin/ambari-nanny.sh $ambariaddress $clustername"
done
}


main () {
 start_nodes_aws
 wait_for_servers
 remove_maintenance_mode
 call_ambari_nanny
}


main
