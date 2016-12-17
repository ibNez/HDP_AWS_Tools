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
  $SSH $server 'sudo adduser -G wheel rundeck'</dev/null
  $SCP id_rsa.pub $server:/tmp/</dev/null
  $SSH $server 'sudo mkdir /home/rundeck/.ssh'</dev/null
  $SSH $server 'sudo chown rundeck:rundeck /home/rundeck/.ssh'</dev/null
  $SSH $server 'sudo chmod 700 /home/rundeck/.ssh'</dev/null
  $SSH $server 'sudo cp /tmp/id_rsa.pub /home/rundeck/.ssh/'</dev/null
  $SSH $server 'sudo chmod 600 /home/rundeck/.ssh/id_rsa.pub'</dev/null
  $SSH $server 'sudo cp /home/rundeck/.ssh/id_rsa.pub /home/rundeck/.ssh/authorized_keys'</dev/null
  $SSH $server 'sudo chmod 600 /home/rundeck/.ssh/authorized_keys'</dev/null
  $SSH $server 'sudo chown rundeck:rundeck /home/rundeck/.ssh/authorized_keys'</dev/null
  $SSH $server 'sudo chown rundeck:rundeck /home/rundeck/.ssh/id_rsa.pub'</dev/null
done
