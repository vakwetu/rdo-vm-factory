#!/bin/sh

set -o errexit

# Source our IPA config for IPA settings
SOURCE_DIR=${SOURCE_DIR:-/mnt}

# global network config
. $SOURCE_DIR/global.conf

. $SOURCE_DIR/ipa.conf

# Save the IPA FQDN and IP for later use
IPA_FQDN=$VM_FQDN
IPA_IP=$VM_IP
IPA_DOMAIN=$VM_DOMAIN

# Source our config for RDO settings
. $SOURCE_DIR/rdo.conf

# Set up and install barbican packages
cp $SOURCE_DIR/barbican.repo /etc/yum.repos.d/barbican.repo
yum install -y openstack-barbican openstack-barbican-api python-barbicanclient

# set write permission for barbican database
chmod 757 /var/lib/barbican

# set ownership of /etc/barbican
chown barbican: /etc/barbican

# install pki-base for Dogtag client libraries
yum install -y pki-base

# configure /etc/barbican/barbican-api.conf
openstack-config --set /etc/barbican/barbican-api.conf dogtag_plugin dogtag_host $IPA_FQDN
openstack-config --set /etc/barbican/barbican-api.conf dogtag_plugin dogtag_port 8443
openstack-config --set /etc/barbican/barbican-api.conf dogtag_plugin pem_path "/etc/barbican/kra-agent.pem"
openstack-config --del /etc/barbican/barbican-api.conf secretstore enabled_secretstore_plugins
openstack-config --set /etc/barbican/barbican-api.conf secretstore enabled_secretstore_plugins dogtag_crypto
openstack-config --del /etc/barbican/barbican-api.conf certificate enabled_certificate_plugins 
openstack-config --set /etc/barbican/barbican-api.conf certificate enabled_certificate_plugins dogtag

# configure barbican-api-paste.ini to talk to keystone
KEYSTONE_URI=http://`hostname`:35357
openstack-config --set /etc/barbican/barbican-api-paste.ini pipeline:barbican_api pipeline "keystone_authtoken context apiapp"
openstack-config --set /etc/barbican/barbican-api-paste.ini filter:keystone_authtoken identity_uri $KEYSTONE_URI
openstack-config --set /etc/barbican/barbican-api-paste.ini filter:keystone_authtoken admin_tenant_name "services"

# copy over IPA PEM file from nfs share
mount -a
cp /share/kra-agent.pem /etc/barbican/kra-agent.pem
chown barbican: /etc/barbican/kra-agent.pem

# restart barbican server
systemctl restart openstack-barbican-api.service

# create users
. /root/keystonerc_admin
openstack user create  --password=orange --email=barbican@example.com barbican
openstack role add --user=barbican --project=services admin
openstack service create --name=barbican --description="Barbican Key Management Service" key-manager
openstack endpoint create --region RegionOne --publicurl http://`hostname`:9311 --internalurl http://`hostname`:9311 barbican

# download image for testing and add to glance
wget -P /root http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
openstack image create --disk-format=qcow2 --container-format=bare --public --file /root/cirros-0.3.4-x86_64-disk.img cirros_0.3.4
