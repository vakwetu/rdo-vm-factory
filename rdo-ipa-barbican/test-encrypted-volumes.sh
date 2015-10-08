#!/bin/sh

set -o errexit

# enable barbican key manager in nova
ENCRYPTION_AUTH_URL=http://`hostname`:5000/v3
ENCRYPTION_API_URL=http://`hostname`:9311/v1/
openstack-config --set /etc/nova/nova.conf keymgr api_class "nova.keymgr.barbican.BarbicanKeyManager"
openstack-config --set /etc/nova/nova.conf keymgr encryption_auth_url $ENCRYPTION_AUTH_URL
openstack-config --set /etc/nova/nova.conf barbican catalog_info key-manager:barbican:public
openstack-config --set /etc/nova/nova.conf barbican endpoint_template $ENCRYPTION_API_URL
openstack-config --set /etc/nova/nova.conf barbican os_region_name RegionOne

# restart nova-api and nova-compute
systemctl restart openstack-nova-api.service
systemctl restart openstack-nova-compute.service
systemctl restart openstack-nova-conductor.service

# enable barbican key manager in cinder

openstack-config --set /etc/cinder/cinder.conf keymgr api_class "cinder.keymgr.barbican.BarbicanKeyManager"
openstack-config --set /etc/cinder/cinder.conf keymgr encryption_auth_url $ENCRYPTION_AUTH_URL
openstack-config --set /etc/cinder/cinder.conf keymgr encryption_api_url $ENCRYPTION_API_URL

# restart nova-api
systemctl restart openstack-cinder-api.service
sleep 10

# create LUKS volume type
openstack volume type create LUKS

# create encryption type
cinder encryption-type-create --cipher aes-xts-plain64 --key_size 512  --control_location front-end LUKS nova.volume.encryptors.luks.LuksEncryptor

# create encrypted volume
openstack volume create --size 1 --type LUKS --image cirros_0.3.4 encrypted_volume

# create unencrypted volume
openstack volume create --size 1 --image cirros_0.3.4 unencrypted_volume

# get network id
netid=`openstack network list|awk '/ public / {print $2}'`

# create compute node
openstack server create --flavor m1.tiny --image cirros_0.3.4 --nic "net-id=$netid" vm-test

# wait till server is up
BOOT_TIMEOUT=${BOOT_TIMEOUT:-300}
ii=$BOOT_TIMEOUT
while [ $ii -gt 0 ] ; do
    if openstack server show vm-test|grep ACTIVE ; then
        break
    fi
    if openstack server show vm-test|grep ERROR ; then
        echo could not create server
        openstack server show vm-test
        exit 1
    fi
    ii=`expr $ii - 1`
done

if [ $ii = 0 ] ; then
    echo server was not active after $BOOT_TIMEOUT seconds
    openstack server show vm-test
    exit 1
fi

# attach encrypted volume to server
openstack server add volume --device /dev/vdc vm-test encrypted_volume

# attach unencrypted volume to server
openstack server add volume --device /dev/vdd vm-test unencrypted_volume
