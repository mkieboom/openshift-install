#!/bin/bash

# Customized version of gshipley's installation script
# source: https://github.com/gshipley/installcentos
export VERSION=${VERSION:="3.9.0"}
export VERSIONSHORT=${VERSIONSHORT:="3.9"}
export CONTAINERIZED=${USERNAME:=False}
export DOMAIN=${DOMAIN:=$(hostname)}
export USERNAME=${USERNAME:=admin}
export PASSWORD=${PASSWORD:=admin}
export IP=${IP:="$(ip route get 8.8.8.8 | awk '{print $NF; exit}')"}
export API_PORT=${API_PORT:="8443"}

export METRICS="False"
export LOGGING="False"


# When on AWS environment, enable 'extra's repo containing ansible etc.
aws=$(grep -s -o 'ec2' /sys/hypervisor/uuid | wc -l)
if [ "$aws" -eq "1" ]; then
   yum-config-manager --enable rhui-REGION-rhel-server-extras
fi

# Install epel release
yum install -y wget
wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -O /tmp/epel-release-latest-7.noarch.rpm
rpm -ivh /tmp/epel-release-latest-7.noarch.rpm

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



# install the packages for Ansible
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

# 
htpasswd -b /etc/origin/master/htpasswd ${USERNAME} ${PASSWORD}
oc adm policy add-cluster-role-to-user cluster-admin ${USERNAME}

systemctl restart origin-master-api

oc login -u ${USERNAME} -p ${PASSWORD} https://$DOMAIN:$API_PORT/

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

#cut -d. -f1,2 3.9.0
#awk -F_ 'BEGIN {OFS="_"} /^>gi/ {print $1,$2} ! /^>gi/ {print}' 3.9.0
#awk -F_ '{print $1 (NF>1? FS $2 : "")}' 3.9.0
#echo '3.9.0' |sed 's/\d\.\d.*//'

