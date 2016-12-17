#!/bin/bash
###########################################################################################################################################################
#  This application will deploy rundeck user keys.


file='/opt/sbin/scp.sh'

if [ -f $file ];
then
   SSH='/opt/sbin/ssh.sh'
   SCP='/opt/sbin/scp.sh'
else
   SSH='ssh'
   SCP='scp'
fi

###########################################################################################################################################################
#  Create User rundeck
cat output/privateIPs | while read server
do
  $SSH $server 'sudo cp /etc/hosts.allow /tmp/' </dev/null
  $SSH $server 'sudo chmod 777 /tmp/hosts.allow' </dev/null
  $SCP $server:/tmp/hosts.allow $PWD/output/ </dev/null
  echo "sshd :10.2.150.216 :allow" >> $PWD/output/hosts.allow
  $SCP $PWD/output/hosts.allow $server:/tmp/ </dev/null
  $SSH $server 'sudo cp -f /tmp/hosts.allow /etc/hosts.allow' </dev/null
done
