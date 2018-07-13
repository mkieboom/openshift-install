#!/bin/bash

# Customized version of gshipley's installation script
# source: https://github.com/gshipley/installcentos
export VERSION=${VERSION:="3.9.0"}
export VERSIONSHORT=$(echo $VERSION |sed "s/.[^.]*$//")
export CONTAINERIZED=${CONTAINERIZED:=False}
export DOMAIN=${DOMAIN:=$(hostname)}
export USERNAME=${USERNAME:=admin}
export PASSWORD=${PASSWORD:=admin}
export IP=${IP:="$(ip route get 8.8.8.8 | awk '{print $NF; exit}')"}
export API_PORT=${API_PORT:="8443"}

export METRICS="False"
export LOGGING="False"


# exit the script when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
RED='\033[0;31m'
NC='\033[0m' # No Color
ERRORHEADER=$'\n\n######## SCRIPT FAILED - LAST COMMAND: #########\n\n'
ERRORFOOTER=$'\n\n######## FIX THE ERROR AND RUN AGAIN #########\n'
trap 'echo -e "${RED}$ERRORHEADER\"${last_command}\" command filed with exit code $?. $ERRORFOOTER${NC}"' EXIT


# When on AWS environment, enable 'extra's repo containing ansible, docker etc.
aws=$(grep -s -o 'ec2' /sys/hypervisor/uuid | wc -l)
if [ "$aws" -eq "1" ]; then
   yum-config-manager --enable rhui-REGION-rhel-server-extras
fi

# Install epel release
epelinstalled=$(rpm -qa|grep epel-release|wc -l)
if [ "$epelinstalled" -eq "0" ]; then
  yum install -y wget
  wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -O /tmp/epel-release-latest-7.noarch.rpm
  rpm -ivh /tmp/epel-release-latest-7.noarch.rpm
fi

# Disable the EPEL repository globally so that is not accidentally used during later steps of the installation
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo

# install the following base packages
yum install -y  telnet wget git zile nano net-tools docker \
                                bind-utils iptables-services \
                                bridge-utils bash-completion \
                                kexec-tools sos psacct openssl-devel \
                                httpd-tools NetworkManager \
                                python-cryptography python2-pip python-devel  python-passlib \
                                java-1.8.0-openjdk-headless "@Development Tools"

# Start docker
echo "Launching docker..."
systemctl start docker
systemctl enable docker
echo "Finished launching docker."

# Start NetworkManager if not already running
systemctl | grep "NetworkManager.*running"
if [ $? -eq 1 ]; then
        systemctl start NetworkManager
        systemctl enable NetworkManager
fi


# Generate ssh keys for ansible to ssh
if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -q -f ~/.ssh/id_rsa -N ""
fi
# Add the generated key to the authorized keys file
if [ -f ~/.ssh/id_rsa.pub ]; then
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        ssh -o StrictHostKeyChecking=no root@$IP "pwd" < /dev/null
fi

# Install the packages for Ansible
yum -y --enablerepo=epel install ansible pyOpenSSL

# Clone the openshift-ansible project
[ ! -d openshift-ansible ] && git clone https://github.com/openshift/openshift-ansible.git

# Checkout the right Openshift release version
cd openshift-ansible && git fetch && git checkout release-${VERSIONSHORT} && cd ..

# Set the /etc/hosts file content
cat <<EOD >> /etc/hosts
${IP}   $(hostname)
EOD

# Set the variables in the inventory.ini file
cp inventory.ini inventory.clone
envsubst < inventory.clone > inventory.ini

# Launch the pre-requisites check
ansible-playbook -i inventory.ini openshift-ansible/playbooks/prerequisites.yml

# Launch the ansible installation to deploy a cluster
ansible-playbook -i inventory.ini openshift-ansible/playbooks/deploy_cluster.yml

# Set the user password and add cluster admin role to user
htpasswd -b /etc/origin/master/htpasswd ${USERNAME} ${PASSWORD}
oc adm policy add-cluster-role-to-user cluster-admin ${USERNAME}

# Restart the origin master api and login
systemctl restart origin-master-api
sleep 3
oc login -u ${USERNAME} -p ${PASSWORD} https://$DOMAIN:$API_PORT/

# Print out the config details
echo "******"
echo "* Your console is https://$DOMAIN:$API_PORT"
echo "* Your username is $USERNAME "
echo "* Your password is $PASSWORD "
echo "*"
echo "* Login using:"
echo "$ oc login -u ${USERNAME} -p ${PASSWORD} https://$DOMAIN:$API_PORT/"
echo "*"
echo "* Add following line to your clients /etc/hosts file:"
echo "${IP}   $(hostname)"
echo "*"
echo "******"
