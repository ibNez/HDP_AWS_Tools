#!/bin/bash

file='/opt/sbin/scp.sh'

if [ -f $file ];
then
   SSH='/opt/sbin/ssh.sh'
   SCP='/opt/sbin/scp.sh'
else
   SSH='ssh'
   SCP='scp'
fi

ambariserviceaccount=$(cat configs/config.yml | grep ambari_service_user | awk '{print $2}')
ambariservicepass=$(cat configs/config.yml | grep ambari_service_password | awk '{print $2}')
clustername=$(cat configs/config.yml | grep clustername | awk '{print $2}')
ambariaddress=$(cat configs/config.yml | grep ambari_address | awk '{print $2}')

##########################################################################################################################
#  Fetch current scoped region
region=$(cat ~/.aws/config | grep region | awk '{print $3}')

counter=1

cat $PWD/output/privateIPs | while read server 
do 
 ((counter++))
 $SSH $server 'hostname' </dev/null 1>$PWD/output/hostname
 
# hostnamecheck=$(cat $PWD/output/hostname | grep "$region")

# if [ "x$hostnamecheck" = "x" ]
# then
#   hostname="$(cat $PWD/output/hostname).us-west-2.compute.internal"
# else
hostname="$(cat $PWD/output/hostname)"
# fi
 
 
 sed -e "s/ambariserviceaccount/$ambariserviceaccount/g" $PWD/templates/ambari-nanny.sh.template > $PWD/output/ambari-nanny.sh.template.1
 sed -e "s/ambariservicepass/$ambariservicepass/g" $PWD/output/ambari-nanny.sh.template.1 > $PWD/output/ambari-nanny.sh.template.2
 sed -e "s/HOSTNAME/$hostname/g" $PWD/output/ambari-nanny.sh.template.2 > $PWD/output/ambari-nanny.sh

 rm -f $PWD/output/ambari-nanny.sh.template.*

 echo "*/5 * * * * root /bin/sh sleep $counter;/usr/local/bin/ambari-nanny.sh $ambariaddress $clustername &" > $PWD/output/run-ambari-nanny
 $SSH $server 'sudo rm -f /tmp/ambari-nanny.sh' </dev/null
 $SSH $server 'sudo rm -f /tmp/run-ambari-nanny' </dev/null
 $SCP $PWD/output/ambari-nanny.sh $server:/tmp/ </dev/null
 $SSH $server 'sudo cp -r /tmp/ambari-nanny.sh /usr/local/bin/' </dev/null
 $SSH $server 'sudo chmod a+x /usr/local/bin/ambari-nanny.sh' </dev/null
 $SCP $PWD/output/run-ambari-nanny $server:/tmp/ </dev/null
 $SSH $server 'sudo cp -f /tmp/run-ambari-nanny /etc/cron.d/' </dev/null
 if (( $counter > 160 ))
 then
   counter=1
 fi
done
