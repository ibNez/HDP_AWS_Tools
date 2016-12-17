#!/bin/bash

######################################################################################################################################
# Check input variables
hdpversion=$(cat configs/config.yml | grep hdpversion | awk '{print $2}')
ambariadmin=$(cat configs/config.yml | grep ambari_user | awk '{print $2}')
ambaripass=$(cat configs/config.yml | grep ambari_password | awk '{print $2}')
clustername=$(cat configs/config.yml | grep clustername | awk '{print $2}')
fs_s3_accesskey=$(cat configs/config.yml | grep fs_s3_accesskey | awk '{print $2}')
fs_s3_awsAccessKeyId=$(cat configs/config.yml | grep fs_s3_awsAccessKeyId | awk '{print $2}')
fs_s3_secret_key=$(cat configs/config.yml | grep fs_s3_secret_key | awk '{print $2}')
fs_s3_awsSecretAccessKey=$(cat configs/config.yml | grep fs_s3_awsSecretAccessKey | awk '{print $2}')
fs_s3_impl=$(cat configs/config.yml | grep fs_s3_impl | awk '{print $2}')
fs_s3a_access_key=$(cat configs/config.yml | grep fs_s3a_access_key | awk '{print $2}')
fs_s3a_awsAccessKeyId=$(cat configs/config.yml | grep fs_s3a_awsAccessKeyId | awk '{print $2}')
fs_s3a_secret_key=$(cat configs/config.yml | grep fs_s3a_secret_key | awk '{print $2}')
fs_s3a_awsSecretAccessKey=$(cat configs/config.yml | grep fs_s3a_awsSecretAccessKey | awk '{print $2}')
fs_s3a_impl=$(cat configs/config.yml | grep fs_s3a_impl | awk '{print $2}')
fs_s3bfs_awsAccessKeyId=$(cat configs/config.yml | grep fs_s3bfs_awsAccessKeyId | awk '{print $2}')
fs_s3n_access_key=$(cat configs/config.yml | grep fs_s3n_access_key | awk '{print $2}')
fs_s3n_awsAccessKeyId=$(cat configs/config.yml | grep fs_s3n_awsAccessKeyId | awk '{print $2}')
fs_s3n_awsSecretAccessKey=$(cat configs/config.yml | grep fs_s3n_awsSecretAccessKey | awk '{print $2}')
fs_s3n_endpoint=$(cat configs/config.yml | grep fs_s3n_endpoint | awk '{print $2}')
fs_s3n_impl=$(cat configs/config.yml | grep fs_s3n_impl | awk '{print $2}')
fs_s3n_secret_key=$(cat configs/config.yml | grep fs_s3n_secret_key | awk '{print $2}')
fs_s3bfs_awsSecretAccessKey=$(cat configs/config.yml | grep fs_s3bfs_awsSecretAccessKey | awk '{print $2}')
fs_s3bfs_impl=$(cat configs/config.yml | grep fs_s3bfs_impl | awk '{print $2}')

#############################################################################################
#  Find HDP version from configuration file
versionwholenumber=$(echo "${hdpversion: -2}")
versionstart=$(echo "${versionwholenumber:0:1}")
versionend=$(echo "${versionwholenumber: -1}")

###############################################################################
#  This is the version number found in the config file
hdpversionnumber=$(echo "$versionstart.$versionend")

mkdir $PWD/output 1>&2>/dev/null

####################################
#  Moved to configuration file
#if [ "x$1" = "x" ]
#then
#  printf "Please provide a name for the new cluster. \n"
#  exit
#else
#  clustername="$1"
#fi

file='/opt/sbin/scp.sh'

if [ -f $file ];
then
   SSH='/opt/sbin/ssh.sh'
   SCP='/opt/sbin/scp.sh'
else
   SSH='ssh'
   SCP='scp'
fi


######################################################################################################################################
# Deploy new cluster nodes
./createbigdatanodes.sh 5 "$clustername"

#######################################################################################################################################
# Validation Check.  Did AWS create nodes?
systemscheck=$(cat $PWD/output/privateIPs)

if [ "x$systemscheck" = "x" ]
then
  printf "No nodes to work with, Exiting.\n"
  exit
fi

######################################################################################################################################
# Check Servers are online after initial reboot.

printf "Waiting for servers to come online."
cat $PWD/output/privateIPs | while read server ; do
 succeeded=$(nc -zv $server 22 | grep 'succeeded')
 printf "Waiting for server: $server to come online.\n"
 printf "Current Status = $succeeded\nWaiting."
 while [ "x$succeeded" = x ]
 do
   printf "."
   sleep 25
   succeeded=$(nc -zv $server 22 | grep 'succeeded')
 done
 printf "\n"
done



######################################################################################################################################
# Setup Variables
printf "Setting up cluster configuration variables.\n"
masternode=$(cat $PWD/output/privateIPs | grep "10." | head -n 1)
printf "Master Node:\n$masternode\n"
slavenodes=$(cat $PWD/output/privateIPs | grep "10." | tail -n 4)
printf "Slave Nodes:\n$slavenodes\n"

#####################################################################################################################################
# Change hostnames and EC2 Instance Names

####################################### Launcher Ambari #############################################################################
#  Rename AWS instance to new name matching hostname change
oldname=$($SSH $masternode 'hostname')
instanceid=$(aws ec2 describe-instances --filters="Name=private-dns-name,Values=$oldname" | grep InstanceId | awk -F'"' '{print $4}')
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername"-launcher

#change hostname for system
if [ "$hdpversion" = "hdp25" ]
then
  $SSH $masternode "sudo su; hostnamectl set-hostname $clustername-launcher.cmcm.net"</dev/null
else
 sed -e  "s/hostname=.*/hostname=$masterhostname/g" $PWD/templates/ambari-agent24.template > $PWD/output/ambari-agent.ini
 sed -e "s/LOCALHOST/"$clustername-launcher"/g" $PWD/templates/network > $PWD/output/network
 $SCP $PWD/output/network $masternode:~/</dev/null
 $SSH $masternode 'sudo cp -f ~/network /etc/sysconfig/'</dev/null
 $SSH $masternode 'sudo reboot'</dev/null
fi


########################################  Master2 ####################################################################
#  Rename AWS instance to new name matching hostname change
slavenode=$(printf "$slavenodes" | head -n 1 | tail -n 1)
oldname=$($SSH $slavenode 'hostname')
instanceid=$(aws ec2 describe-instances --filters="Name=private-dns-name,Values=$oldname" | grep InstanceId | awk -F'"' '{print $4}')
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername"-nn-hist-zk

#change hostname for system
if [ "$hdpversion" = "hdp25" ]
then
  $SSH $slavenodes "sudo su; hostnamectl set-hostname $clustername-nn-hist-zk.cmcm.net"</dev/null
else
 sed -e "s/LOCALHOST/"$clustername"-nn-hist-zk/g" $PWD/templates/network > $PWD/output/network
 $SCP $PWD/output/network $slavenode:~/
 $SSH $(printf "$slavenodes" | head -n 1 | tail -n 1) 'sudo cp -f ~/network /etc/sysconfig/'
 $SSH $(printf "$slavenodes" | head -n 1 | tail -n 1) 'sudo reboot'
fi

#########################################  Master3 ###################################################################################
#  Rename AWS instance to new name matching hostname change
slavenode=$(printf "$slavenodes" | head -n 2 | tail -n 1)
oldname=$($SSH $slavenode 'hostname')
instanceid=$(aws ec2 describe-instances --filters="Name=private-dns-name,Values=$oldname" | grep InstanceId | awk -F'"' '{print $4}')
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername"-rm-zk

#change hostname for system
if [ "$hdpversion" = "hdp25" ]
then
  $SSH $slavenode "sudo su; hostnamectl set-hostname $clustername-rm-zk.cmcm.net"</dev/null
else
 sed -e "s/LOCALHOST/"$clustername"-rm-zk/g" $PWD/templates/network > $PWD/output/network
 $SCP $PWD/output/network $slavenode:~/
 $SSH $slavenode 'sudo cp -f ~/network /etc/sysconfig/'
 $SSH $slavenode 'sudo reboot'
fi

#########################################  Master4 ###################################################################################
#  Rename AWS instance to new name matching hostname change
slavenode=$(printf "$slavenodes" | head -n 3 | tail -n 1)
oldname=$($SSH $slavenode 'hostname')
instanceid=$(aws ec2 describe-instances --filters="Name=private-dns-name,Values=$oldname" | grep InstanceId | awk -F'"' '{print $4}')
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername"-nn-rm-zk

#change hostname for system
if [ "$hdpversion" = "hdp25" ]
then
  $SSH $slavenode "sudo su; hostnamectl set-hostname $clustername-nn-rm-zk.cmcm.net"</dev/null
else
 sed -e "s/LOCALHOST/"$clustername"-nn-rm-zk/g" $PWD/templates/network > $PWD/output/network
 $SCP $PWD/output/network $slavenode:~/
 $SSH $slavenode 'sudo cp -f ~/network /etc/sysconfig/'
 $SSH $slavenode 'sudo reboot'
fi

#  Rename AWS instance to new name matching hostname change
slavenode=$(printf "$slavenodes" | head -n 4 | tail -n 1)
oldname=$($SSH $slavenode 'hostname')
instanceid=$(aws ec2 describe-instances --filters="Name=private-dns-name,Values=$oldname" | grep InstanceId | awk -F'"' '{print $4}')
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername"-hive-Webhcat

#change hostname for system
if [ "$hdpversion" = "hdp25" ]
then
  $SSH $slavenode "sudo su; hostnamectl set-hostname $clustername-hive-Webhcat.cmcm.net"</dev/null
else
 sed -e "s/LOCALHOST/"$clustername"-hive-Webhcat/g" $PWD/templates/network > $PWD/output/network
 $SCP $PWD/output/network $slavenode:~/
 $SSH $slavenode 'sudo cp -f ~/network /etc/sysconfig/'
 $SSH $slavenode 'sudo reboot'
 sleep 15
fi



######################################################################################################################################
# Check Servers are online after initial reboot.

printf "Waiting for servers to come online."
cat $PWD/output/privateIPs | while read server ; do
 succeeded=$(nc -zv $server 22 | grep 'succeeded')
 printf "Waiting for server: $server to come online.\n"
 printf "Current Status = $succeeded\nWaiting."
 while [ "x$succeeded" = x ]
 do
   printf "."
   sleep 25
   succeeded=$(nc -zv $server 22 | grep 'succeeded')
 done
 printf "\n"
done


masterhostname="$clustername-launcher.cmcm.net"
slavehostnames="$clustername-nn-hist-zk.cmcm.net
$clustername-rm-zk.cmcm.net
$clustername-nn-rm-zk.cmcm.net
$clustername-hive-Webhcat.cmcm.net"


echo "127.0.0.1   localhost   localhost.localdomain" > $PWD/output/hosts
printf "$clustername-launcher.cmcm.net
$clustername-nn-hist-zk.cmcm.net
$clustername-rm-zk.cmcm.net
$clustername-nn-rm-zk.cmcm.net
$clustername-hive-Webhcat.cmcm.net" > $PWD/output/hostnames

paste $PWD/output/privateIPs $PWD/output/hostnames >> $PWD/output/hosts

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/output/hosts $server:~/ </dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp -f ~/hosts /etc/hosts' </dev/null ; done


##################################################
# Update configuration file for ambari-agent, ambari-agent.ini.  Here we are adding the new hostname for the master.  Starting Agent.

if [ "$hdpversion" = "hdp25" ]
then
 sed -e  "s/hostname=.*/hostname=$masterhostname/g" $PWD/templates/ambari-agent25.template > $PWD/output/ambari-agent.ini
else
 sed -e  "s/hostname=.*/hostname=$masterhostname/g" $PWD/templates/ambari-agent24.template > $PWD/output/ambari-agent.ini
fi

cat $PWD/output/privateIPs | grep "10." | while read server ; do $SCP $PWD/output/ambari-agent.ini $server:~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/ambari-agent.ini /etc/ambari-agent/conf/'</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server  'sudo ambari-agent restart'</dev/null ; done


#####################################################################################################################################
# Deploy Ambari on new Masternode

if [ "$hdpversion" = "hdp25" ]
then
 $SSH $masternode 'sudo yum -y install ambari-server'
else
 $SSH $masternode 'sudo mv /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo'
 $SSH $masternode 'sudo mv /etc/yum.repos.d/kingsoft.repo /etc/yum.repos.d/kingsoft.repo.back'
 $SSH $masternode 'sudo yum --disablerepo "*" --enablerepo "HDP-2.4.2.0" --enablerepo "HDP-UTILS-1.1.0.20" --enablerepo "Updates-ambari-2.2.1.0" install ambari-server'
fi



if [ "$hdpversion" = "hdp25" ]
then
 $SSH $masternode '(echo y; echo n; echo 1; echo y; echo n) | sudo ambari-server setup'
else
 $SSH $masternode '(echo n; echo 1; echo y; echo n) | sudo ambari-server setup'
fi
$SSH $masternode 'sudo echo "api.csrfPrevention.enabled=false" >> /etc/ambari-server/conf/ambari.properties'
$SSH $masternode 'sudo ambari-server start'


########################################################################################################################################
# Update host.allow for new server

sed -e "s/10.2.150.122/$masternode/g" $PWD/templates/hosts.allow.template > $PWD/output/hosts.allow

printf "Hostname file outputted to hostnames.\n Copy hosts.allow to all new hosts for access from ambari.\n"

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/output/hosts.allow "$server":~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/hosts.allow /etc/hosts.allow'</dev/null ; done


############################################################################################################################################
# Validate that agents have registered in Ambari.

sleep 5

printf "Validating Agent Install and Registered with Ambari...\n"
ambarihostlist=$(curl -i -H "X-Requested-By: ambari" -u "$ambariadmin":"$ambaripass" -X GET "http://$masternode:8080/api/v1/hosts" | grep host_name)
printf "\n$ambarihostlist"


############################################################################################################################################
# Setup Ambari Blueprint

sed -e "s/TEMPLATECLUSTERNAME/$clustername/g" $PWD/templates/hdfs_ha_blueprint > $PWD/output/"$clustername"_blueprint.json.1
sed -e "s/HDPVERSION/$hdpversionnumber/g" $PWD/output/"$clustername"_blueprint.json.1 > $PWD/output/"$clustername"_blueprint.json.2
sed -e "s/fs_s3_accesskey/$fs_s3_accesskey/g" $PWD/output/"$clustername"_blueprint.json.2 > $PWD/output/"$clustername"_blueprint.json.3
sed -e "s/fs_s3_awsAccessKeyId/$fs_s3_awsAccessKeyId/g" $PWD/output/"$clustername"_blueprint.json.3 > $PWD/output/"$clustername"_blueprint.json.4
sed -e "s/fs_s3_secret_key/$fs_s3_secret_key/g" $PWD/output/"$clustername"_blueprint.json.4 > $PWD/output/"$clustername"_blueprint.json.5
sed -e "s/fs_s3_awsSecretAccessKey/$fs_s3_awsSecretAccessKey/g" $PWD/output/"$clustername"_blueprint.json.5 > $PWD/output/"$clustername"_blueprint.json.6
sed -e "s/fs_s3_impl/$fs_s3_impl/g" $PWD/output/"$clustername"_blueprint.json.6 > $PWD/output/"$clustername"_blueprint.json.7
sed -e "s/fs_s3a_access_key/$fs_s3a_access_key/g" $PWD/output/"$clustername"_blueprint.json.7 > $PWD/output/"$clustername"_blueprint.json.8
sed -e "s/fs_s3a_awsAccessKeyId/$fs_s3a_awsAccessKeyId/g" $PWD/output/"$clustername"_blueprint.json.8 > $PWD/output/"$clustername"_blueprint.json.9
sed -e "s/fs_s3a_secret_key/$fs_s3a_secret_key/g" $PWD/output/"$clustername"_blueprint.json.9 > $PWD/output/"$clustername"_blueprint.json.10
sed -e "s/fs_s3a_awsSecretAccessKey/$fs_s3a_awsSecretAccessKey/g" $PWD/output/"$clustername"_blueprint.json.10 > $PWD/output/"$clustername"_blueprint.json.11
sed -e "s/fs_s3a_impl/$fs_s3a_impl/g" $PWD/output/"$clustername"_blueprint.json.11 > $PWD/output/"$clustername"_blueprint.json.12
sed -e "s/fs_s3bfs_awsAccessKeyId/$fs_s3bfs_awsAccessKeyId/g" $PWD/output/"$clustername"_blueprint.json.12 > $PWD/output/"$clustername"_blueprint.json.13
sed -e "s/fs_s3n_access_key/$fs_s3n_access_key/g" $PWD/output/"$clustername"_blueprint.json.13 > $PWD/output/"$clustername"_blueprint.json.14
sed -e "s/fs_s3n_awsAccessKeyId/$fs_s3n_awsAccessKeyId/g" $PWD/output/"$clustername"_blueprint.json.14 > $PWD/output/"$clustername"_blueprint.json.15
sed -e "s/fs_s3n_awsSecretAccessKey/$fs_s3n_awsSecretAccessKey/g" $PWD/output/"$clustername"_blueprint.json.15 > $PWD/output/"$clustername"_blueprint.json.16
sed -e "s/fs_s3n_endpoint/$fs_s3n_endpoint/g" $PWD/output/"$clustername"_blueprint.json.16 > $PWD/output/"$clustername"_blueprint.json.17
sed -e "s/fs_s3n_impl/$fs_s3n_impl/g" $PWD/output/"$clustername"_blueprint.json.17 > $PWD/output/"$clustername"_blueprint.json.18
sed -e "s/fs_s3n_secret_key/$fs_s3n_secret_key/g" $PWD/output/"$clustername"_blueprint.json.18 > $PWD/output/"$clustername"_blueprint.json.19
sed -e "s/fs_s3bfs_awsSecretAccessKey/$fs_s3bfs_awsSecretAccessKey/g" $PWD/output/"$clustername"_blueprint.json.19 > $PWD/output/"$clustername"_blueprint.json.20
sed -e "s/fs_s3bfs_impl/$fs_s3bfs_impl/g" $PWD/output/"$clustername"_blueprint.json.20 > $PWD/output/"$clustername"_blueprint.json.21
sed -e "s/ambari_password/$ambaripass/g" $PWD/output/"$clustername"_blueprint.json.21 > $PWD/output/"$clustername"_blueprint.json.22
sed -e "s/TEMPLATEBLUEPRINTNAME/$clustername-blueprint/g" $PWD/output/"$clustername"_blueprint.json.22 > $PWD/output/"$clustername"_blueprint.json

rm $PWD/output/"$clustername"_blueprint.json.*


############################################################################################################################################
# Setup Ambari Template
printf "Building Ambari Template.\n"

i=1
declare -A hostname=[]
echo "" >> output/hostnames
while IFS= read -r server ; do
    hostname[$i]=$server
    i=$[i+1]
done < $PWD/output/hostnames
printf "\nSetting up configuration for server Master node: ${hostname[1]}\n"
sed -e "s/ip-10-2-151-210.us-west-2.compute.internal/${hostname[1]}/g" $PWD/templates/blueprint-template > $PWD/output/blueprint-template.1
printf "\nSetting up configuration for server ${hostname[2]}\n"
sed -e "s/ip-10-2-151-211.us-west-2.compute.internal/${hostname[2]}/g" $PWD/output/blueprint-template.1 > $PWD/output/blueprint-template.2
printf "\nSetting up configuration for server ${hostname[3]}\n"
sed -e "s/ip-10-2-151-212.us-west-2.compute.internal/${hostname[3]}/g" $PWD/output/blueprint-template.2 > $PWD/output/blueprint-template.3
printf "\nSetting up configuration for server ${hostname[4]}\n"
sed -e "s/ip-10-2-151-213.us-west-2.compute.internal/${hostname[4]}/g" $PWD/output/blueprint-template.3 > $PWD/output/blueprint-template.4
printf "\nSetting up configuration for server ${hostname[5]}\n"
sed -e "s/ip-10-2-151-214.us-west-2.compute.internal/${hostname[5]}/g" $PWD/output/blueprint-template.4 > $PWD/output/blueprint-template.5

sed -e "s/ha-hdfs/"$clustername"-blueprint/g" $PWD/output/blueprint-template.5 > $PWD/output/$clustername-template.json

rm -f $PWD/output/blueprint-template.*


############################################################################################################################################
# Install blueprint with ambari server
printf "Installing Blueprint.\n"
curl -H "X-Requested-By: ambari" -X POST -d @$PWD/output/"$clustername"_blueprint.json -u "$ambariadmin":"$ambaripass" $masternode:8080/api/v1/blueprints/"$clustername"-blueprint


############################################################################################################################################
# Deploy cluster with template
printf "Deploying cluster template.\n"
curl -H "X-Requested-By: ambari" -X POST -d @$PWD/output/"$clustername"-template.json -u "$ambariadmin":"$ambaripass" $masternode:8080/api/v1/clusters/"$clustername"


#################################################################################################################################
# Add ambari-nanny script and cron to run it.  This script will keep services up.
./deploy_nanny.sh

############################################################################################################################################
# Print End Info
printf "Master Node:\n$masternode\n"
printf "Slave Nodes:\n$slavenodes\n"
printf "Master Hostname:\n$masterhostname\n"
printf "Slave Hostnames:\n$slavehostnames\n"
printf "Ambari URL: http://$masternode:8080\n"
