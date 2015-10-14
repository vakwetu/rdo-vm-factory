#!/bin/sh

set -o errexit

# disable selinux
setenforce 0

# Source our IPA config for IPA settings
SOURCE_DIR=${SOURCE_DIR:-/mnt}
SOURCE_DIR=/root

# install haproxy
yum install haproxy

BARBICAN_HAPROXY_PORT=9312
SSL_CERT=/etc/httpd/conf/server.crt
SSL_KEY=/etc/httpd/conf/server.key
KEYTAB=/etc/httpd/conf/openstack.keytab
HAPROXY_CERTS=/etc/haproxy/cert.pem

# set up barbican haproxy
openstack-config --set /etc/barbican/barbican-api.conf DEFAULT bind_host 127.0.0.1
openstack-config --set /etc/barbican/barbican-api.conf DEFAULT bind_port $BARBICAN_HAPROXY_PORT

# restart barbican
systemctl restart openstack-barbican-api.service

# update barbican endpoints
mysql -vv -u root keystone -e "update endpoint set url=\"https://`hostname`:9311\" where url like \"http://%:9311\";"

# copy certs for haproxy
cat $SSL_CERT $SSL_KEY  > $HAPROXY_CERTS

# set haproxy cert permissions
chown haproxy: $HAPROXY_CERTS
chmod 0600 $HAPROXY_CERTS

# install config file
cp $SOURCE_DIR/haproxy.cfg /etc/haproxy/haproxy.cfg

# restart haproxy
systemctl restart haproxy.service

# fix up nova config
openstack-config --set /etc/nova/nova.conf barbican endpoint_template https://rdo.rdodom.test:9311/v1/

# restart nova
systemctl restart openstack-nova-api.service
systemctl restart openstack-nova-compute.service

# enable selinux
setenforce 1
