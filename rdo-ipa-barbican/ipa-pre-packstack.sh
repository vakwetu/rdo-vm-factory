#!/bin/sh

set -o errexit

# disable selinux
setenforce 0

# Source our IPA config for IPA settings
SOURCE_DIR=${SOURCE_DIR:-/mnt}
SOURCE_DIR=/root

# global network config
. $SOURCE_DIR/global.conf

. $SOURCE_DIR/ipa.conf

IPA_DOMAIN=$VM_DOMAIN
SSL_CERT=/etc/httpd/conf/server.crt
SSL_KEY=/etc/httpd/conf/server.key
KEYTAB=/etc/httpd/conf/openstack.keytab

# install httpd
yum install -y httpd

# start certmonger
systemctl restart certmonger.service

# kinit
klist &>/dev/null || echo $IPA_PASSWORD | kinit admin@${IPA_REALM}

# add openstack service
ipa service-add HTTP/`hostname`@${IPA_REALM}

# get cert
ipa-getcert request -w -f $SSL_CERT -k $SSL_KEY -D "`hostname`" -K HTTP/`hostname`

# restart httpd
systemctl restart httpd.service

# get keytab
ipa-getkeytab -s ipa.$IPA_DOMAIN -k $KEYTAB -p HTTP/`hostname`@${IPA_REALM}

# set keytab permissions
chown apache:apache $KEYTAB
chmod 0600 $KEYTAB

# re-enable selinux
setenforce 1


