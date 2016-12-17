#!/bin/bash
#########################################################################################################################
# Check for initial parameters.
hdpversion=$(cat configs/config.yml | grep hdpversion | awk '{print $2}')
ami=$(cat configs/config.yml | grep ami | awk '{print $2}')
flavor=$(cat configs/config.yml | grep instance_type | awk '{print $2}')
mappingfile=$(cat configs/config.yml | grep mapping_file | awk '{print $2}')
subnet=$(cat configs/config.yml | grep subnet_id | awk '{print $2}')

if [ "x$1" = "x" ]
then
 printf "How many instances?\n"
 exit
else
  numberofinstances="$1"
fi

if [ "x$2" = "x"  ]
then
  printf "Provide a cluster name.\n"
  exit
else
  clustername="$2"
fi


mkdir $PWD/output 1>&2>/dev/null
rm -f /var/lib/rundeck/.ssh/known_hosts 1>&2>/dev/null
rm -f $PWD/output/privateIPs 1>&2>/dev/null

##########################################################################
#  Find nodetype to create
#  MASTER
#  NODEMANAGER
#MOVED TO CONFIG FILE

#if [ "x$3" = "x"  ]
#then
#  printf "\nDefault mapping used: 2048TB"
#  mappingfile=mapping160.json
#  nodetype="MASTER"
#elif [ "$3" = "MASTER" ] || [ "$3" = DATANODE ]
#then
#  printf "\nNode type given: $3"
#  mappingfile=mapping1024.json
#  nodetype="$3"
#elif [ "$3" = "NODEMANAGER" ]
#then
#  printf "\nNode type given: $3"
#  mappingfile=mapping160.json
#  nodetype="$3"
#else
#  printf "\nNot a valide node type: NODEMANAGER or MASTER\n"
#  exit
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

##########################################################################################################################
#  Fetch current scoped region
region=$(cat ~/.aws/config | grep region | awk '{print $3}')

##########################################################################################################################
# This will create the requested number of EC2 instances

if [ "$region" = "us-west-1" ]
 then
   output=$(aws ec2 run-instances --image-id $ami --count $numberofinstances --instance-type "$flavor" --key-name tony.philip --security-group-ids sg-9f6b71fd --subnet-id subnet-e9df80b0 --block-device-mappings file://$PWD/configs/"$mappingfile" --associate-public-ip-address)
elif [ "$region" = "us-west-2" ]
 then
  output=$(aws ec2 run-instances --image-id $ami --count $numberofinstances --instance-type "$flavor" --key-name tony.philip --security-group-ids sg-8218d0e7 sg-5ad6a93c --subnet-id "$subnet" --block-device-mappings file://$PWD/configs/"$mappingfile" --associate-public-ip-address)
else
   printf "\n Unknown region: $region"
   exit
fi
 echo "$output"
 instanceIDs=$(echo "$output" | grep InstanceId | awk -F'"' '{print $4}')
 privateIPs=$(echo "$output" | grep PrivateIpAddress | awk -F'"' '{print $4}' | sort -u)
 printf "Instance IDs: \n$instanceIDs\n"
 printf "Private IPs: $privateIPs\n"

if [ "x$output" = x ]
then
  printf "Request for systems from AWS has failed.  EXITING.\n"
  exit
fi


##########################################################################################################################
# This will add the tags to the newly created instances

echo "$instanceIDs" | while read instanceid ; do aws ec2 create-tags --resources $instanceid --tags Key=Name,Value="$clustername" Key=cluster,Value="$clustername" Key=department,Value=bigdata Key=owners,Value=stephen.brodsky:tony.philip Key=product,Value="$clustername"-node  ; done
printf "\nInstances Tagged\n"


##########################################################################################################################
# This will find available Elastic IP addresses in the 52.38.190 space.

if [ "$region" = "us-west-1" ]
 then
   allocationIDs=$(aws ec2 describe-addresses --region us-west-1 --filter "Name=public-ip,Values=52.38.190.*" | grep -B 1 AllocationId |  xargs -n 5 | grep -v 'PublicIp' | awk '{print $4}')
elif [ "$region" = "us-west-2" ]
 then
   aws ec2 describe-addresses --region us-west-2 --filter "Name=public-ip,Values=52.38.190.*" | grep -B 1 AllocationId |  xargs -n 5 | grep -v 'PublicIp' | awk '{print $4}' > $PWD/output/EIPs
   aws ec2 describe-addresses --region us-west-2 --filter "Name=public-ip,Values=35.162.255.*" | grep -B 1 AllocationId |  xargs -n 5 | grep -v 'PublicIp' | awk '{print $4}' >> $PWD/output/EIPs
   allocationIDs=$(cat $PWD/output/EIPs)
else
   printf "\n Unknown region: $region"
   exit
fi

echo "$allocationIDs" > $PWD/output/allocationIDs
echo "$instanceIDs" > $PWD/output/instanceIDs
echo "$privateIPs" | grep "10." > $PWD/output/privateIPs

##########################################################################################################################
# This will group the EIP allocationIDs with the new instance IDs

instancesandEIPs=$(paste $PWD/output/allocationIDs $PWD/output/instanceIDs)



############################################################################################################################
# This will associate EIPs with the new instances

 echo "$instancesandEIPs" | while read allocationid instanceid ; do
  if [ "x$instanceid" = "x" ]
  then
   break;
  fi
  pending=$(aws ec2 describe-instances --instance-ids $instanceid | grep '"Name": "pending"')
  
  printf "Waiting for Instance state to change to running."
  while [ "x$pending" != "x" ]
  do
   printf "."
   sleep 15
   pending=$(aws ec2 describe-instances --instance-ids $instanceid | grep '"Name": "pending"')
  done
  
  printf "\nAssociating EIP: $allocationid with Instance ID: $instanceid\n"
  aws ec2 associate-address --instance-id $instanceid --allocation-id $allocationid
 done


############################################################################################################
# Now we need to wait for the mounts to finish being created and attatched to the instance.

printf "Waiting for Volumes to attatch."
sleep 25
printf "."
sleep 25

###############################################################################################################
# Wait for servers to come backonline
printf "Waiting for servers to come online.\n"

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


#############################################################################################################
# Here we are creating hostnames file, converting the ip addresses into internal DNS names.

printf "\nCreating hostnames file.\n"

cat $PWD/output/privateIPs | while read server ; do $SSH $server 'hostname'</dev/null ; done > $PWD/output/hostnames.tmp
cat $PWD/output/hostnames.tmp | awk '{print $1".us-west-2.compute.internal"}' > $PWD/output/hostnames
rm -f $PWD/output/hostnames.tmp

##############################################################################################################
# Now we need to upload the hosts.allow we have precofigured with the cluster ambari/deployement node.

#printf "Hostname file $PWD/outputted to hostnames.\n Copy hosts.allow to all new hosts for access from ambari node.\n"


#cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/templates/hosts.allow.template $server:~/</dev/null ; done 
#cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp -f ~/hosts.allow.template /etc/hosts.allow'</dev/null ; done

##############################################################################################################
# Create Repository and setup packages.

printf "Setting up HDP repository and package prerequirements.\n"

if [ "$hdpversion" = "hdp25" ]
then
 echo "not needed"
# MOVED INTO BASE IMAGE
# cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo wget -P /etc/yum.repos.d/ wget http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.4.0.1/ambari.repo'</dev/null ; done
# cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo wget -P /etc/yum.repos.d/ wget http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.5.0.0/hdp.repo'</dev/null ; done 
# cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo `dates-ambari-2.4.0.1" clean all' ; done
# cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum -y install wget'</dev/null 2> /dev/null  ; done
# Registering the system in spacewalk



printf "\n Registering in Spacewalk.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo rhnreg_ks --force --activationkey 1-8cb7b51ba22db2a408cf5c33c220524e --serverUrl https://spacewalk.cmcm.net/XMLRPC'</dev/null 2> /dev/null  ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo rhn-channel -a -c hdp2.5 --user="Spacewalk_Agent" --password="xz940lm"'</dev/null 2> /dev/null  ; done
cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/configs/rhnplugin.conf $server:~/ </dev/null 2> /dev/null  ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp -f ~/rhnplugin.conf /etc/yum/pluginconf.d/'</dev/null 2> /dev/null  ; done


################################################################################################################
# Upload and put in place fstab file for mount configuration

printf "Setting up fstab with mount information.\n"

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/configs/fstab.CentOS7 "$server":~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server  'sudo cp -f ~/fstab.CentOS7 /etc/fstab'</dev/null  ; done


else
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo wget -P /etc/yum.repos.d/ wget http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.2.1.0/ambari.repo'</dev/null ; done 
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo wget -P /etc/yum.repos.d/ wget http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.4.2.0/hdp.repo'</dev/null ; done 
# cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum --disablerepo "*" --enablerepo "HDP-2.4.2.0" --enablerepo "HDP-UTILS-1.1.0.20" --enablerepo "Updates-ambari-2.2.1.0" clean all'</dev/null 2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mv /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo'</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mv /etc/yum.repos.d/kingsoft.repo /etc/yum.repos.d/kingsoft.repo.back'</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum -y install yum-plugin-fastestmirror'</dev/null 2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum -y remove snappy'</dev/null 2> /dev/null  ; done 


###############################################################################################################
# Create hdfs service account user. This user will be used to deploy systems in the environment.

 printf "Setting local user account for hdfs service account.\n"

 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo useradd hdfs -G wheel || id hdfs'</dev/null 2> /dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mkdir -p /home/hdfs/.ssh'</dev/null 2> /dev/null ; done

###############################################################################################################
# Copy public keys to servers for hdfs account.

 printf "Copying keys for hdfs to user .ssh.\n"

 cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/configs/id_rsa.pub "$server":~/</dev/null 2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/id_rsa.pub /home/hdfs/.ssh/'</dev/null 2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/id_rsa.pub /home/hdfs/.ssh/authorized_keys'</dev/null 2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo chown -R hdfs:hdfs /home/hdfs/.ssh'</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo chown hdfs /home/hdfs/.ssh/id_rsa.pub'</dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo chown hdfs /home/hdfs/.ssh/authorized_keys'</dev/null  2> /dev/null ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo chmod 600 /home/hdfs/.ssh/*'</dev/null  2> /dev/null  ; done
 cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo chmod 700 /home/hdfs/.ssh'</dev/null 2> /dev/null ; done


################################################################################################################
# Upload and put in place fstab file for mount configuration

printf "Setting up fstab with mount information.\n"

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/configs/fstab "$server":~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server  'sudo cp ~/fstab /etc/fstab'</dev/null  ; done

################################################################################################################
# Ensure /data and /data1 folder exist

printf "Creating /data and /data1 folders for mount points of EBS volumes.\n"

cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mkdir /data '</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mkdir /data1'</dev/null ; done

fi

################################################################################################################
# Create disk partitions.

printf "Creating partition on disk1.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server '(echo o; echo n; echo p; echo 1; echo ; echo; echo w) | sudo fdisk /dev/xvdb'</dev/null ; done
printf "Creating partition on disk2.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server '(echo o; echo n; echo p; echo 1; echo ; echo; echo w) | sudo fdisk /dev/xvdc'</dev/null ; done

################################################################################################################
# Format disks

printf "Formatting disk1.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mkfs.xfs -f /dev/xvdb'</dev/null ; done
printf "Formatting disk2.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mkfs.xfs -f /dev/xvdc'</dev/null ; done
#./run_all.sh privateIPs 'sudo umount -a'
#./run_all.sh privateIPs 'sudo mount -a'


################################################################################################################
# Reboot system for configuration check
printf "Rebooting systems for finalization of node configuration.\n"
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo shutdown -r now'</dev/null ; done

######################################################################################################################################
# Setup Variables
printf "Setting up cluster configuration variables"
masternode=$(cat $PWD/output/privateIPs | grep "10." | head -n 1)
printf "Master Node:\n$masternode\n"
slavenodes=$(cat $PWD/output/privateIPs | grep "10." | tail -n 4)
printf "Slave Nodes:\n$slavenodes\n"
masterhostname=$(head -n 1 $PWD/output/hostnames)
printf "Master Hostname:\n$masterhostname\n"
slavehostnames=$(tail -n 4 $PWD/output/hostnames)
printf "Slave Hostnames:\n$slavehostnames\n"


###############################################################################################################
# Wait for servers to come backonline
printf "Waiting for servers to come online.\n"
sleep 25

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

#####################################################################################################################################
# Deploy Ambari agent 

#cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mv /etc/yum.repos.d/CentOS-Base.repo.bak /etc/yum.repos.d/CentOS-Base.repo'</dev/null ; done
#cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo mv /etc/yum.repos.d/kingsoft.repo /etc/yum.repos.d/kingsoft.repo.back'</dev/null ; done
#cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum -y --enablerepo "base" --enablerepo "HDP-2.5.0.0" --enablerepo "HDP-UTILS-1.1.0.21" --enablerepo "Updates-ambari-2.4.0.1" install ambari-agent'</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo yum -y install ambari-agent'</dev/null ; done

########################################################################################################################################
# Update host.allow for new server

sed -e "s/10.2.150.122/$masternode/g" $PWD/templates/hosts.allow.template > $PWD/output/hosts.allow

printf "Hostname file outputted to hostnames.\n Copy hosts.allow to all new hosts for access from ambari.\n"

cat $PWD/output/privateIPs | while read server ; do $SCP $PWD/output/hosts.allow "$server":~/</dev/null ; done
cat $PWD/output/privateIPs | while read server ; do $SSH $server 'sudo cp ~/hosts.allow /etc/hosts.allow'</dev/null ; done


################################################################################################################
# END Output some results

printf "Process complete.  Nodes deployed: \n$privateIPs\n"

printf "Hostnames for ambari:\n"
cat $PWD/output/hostnames

