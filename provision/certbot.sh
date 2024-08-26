#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_certbot()
{
	tell_status "installing certbot"
	pkg install -y py38-certbot
}

install_deploy_haproxy()
{
	store_config "$_deploy/deploy/haproxy" <<'EO_LE_HAPROXY_DEPLOY'
#!/usr/bin/env python3.8

import os
import re
import sys

lineage=os.environ.get('RENEWED_LINEAGE')

# If nothing renewed, exit
if not lineage:
    sys.exit()

# From the linage, we strip the 'domain name', which is the last part
# of the path.
result = re.match(r'.*/live/(.+)$', lineage)

# If we can not recognize the path, we exit with 1
if not result:
    sys.exit(1)

# Extract the domain name
domain = result.group(1)

# Define a path for HAproxy where you want to write the .pem file.
deploy_path="/data/haproxy/ssl.d/" + domain + ".pem"

# The source files can be found in below paths, constructed with the lineage
# path
source_key = lineage + "/privkey.pem"
source_chain = lineage + "/fullchain.pem"

# HAproxy requires to combine the key and chain in one .pem file
with open(deploy_path, "w") as deploy, \
        open(source_key, "r") as key, \
        open(source_chain, "r") as chain:
    deploy.write(key.read())
    deploy.write(chain.read())

EO_LE_HAPROXY_DEPLOY

	tee "$_deploy/post/haproxy" <<'EO_LE_HAPROXY_POST'
#!/bin/sh
jexec haproxy service haproxy restart
EO_LE_HAPROXY_POST

	chmod 755 "$_deploy/deploy/haproxy"
	chmod 755 "$_deploy/post/haproxy"
}

install_deploy_dovecot()
{
	tee "$_deploy/deploy/dovecot" <<'EO_LE_DOVECOT_DEPLOY'
#!/usr/bin/env python3.8

import os
import re
import sys

# Certbot sets an environment variable RENEWED_LINEAGE, which points to the
# path of the renewed certificate. We use that path to determine and find
# the files for the currently renewed certificated
lineage=os.environ.get('RENEWED_LINEAGE')

# If nothing renewed, exit
if not lineage:
    sys.exit()

# From the linage, we strip the 'domain name', which is the last part
# of the path.
result = re.match(r'.*/live/(.+)$', lineage)

# If we can not recognize the path, we exit with 1
if not result:
    sys.exit(1)

# Extract the domain name
domain = result.group(1)

deploy_crt_path="/data/dovecot/etc/ssl/certs/" + domain + ".pem"
deploy_key_path="/data/dovecot/etc/ssl/private/" + domain + ".pem"

source_key = lineage + "/privkey.pem"
source_chain = lineage + "/fullchain.pem"

# HAproxy requires to combine the key and chain in one .pem file
with open(deploy_crt_path, "w") as deploy, \
        open(source_chain, "r") as chain:
    deploy.write(chain.read())

with open(deploy_key_path, "w") as deploy, \
        open(source_key, "r") as key: \
    deploy.write(key.read())

EO_LE_DOVECOT_DEPLOY

	tee "$_deploy/deploy/dovecot" <<'EO_LE_DOVECOT_POST'
#!/bin/sh
jexec dovecot service dovecot restart
EO_LE_DOVECOT_POST

	chmod 755 "$_deploy/deploy/dovecot"
	chmod 755 "$_deploy/post/dovecot"
}

install_deploy_haraka()
{
	tee "$_deploy/deploy/haraka" <<'EO_LE_HARAKA_DEPLOY'
#!/usr/bin/env python3.8

import os
import re
import sys

lineage=os.environ.get('RENEWED_LINEAGE')

if not lineage:
    sys.exit()

# From the linage, we strip the 'domain name', which is the last part
# of the path.
result = re.match(r'.*/live/(.+)$', lineage)

# If we can not recognize the path, we exit with 1
if not result:
    sys.exit(1)

# Extract the domain name
domain = result.group(1)

deploy_path="/data/haraka/config/tls/" + domain + ".pem"

source_key = lineage + "/privkey.pem"
source_chain = lineage + "/fullchain.pem"

# HAproxy requires to combine the key and chain in one .pem file
with open(deploy_path, "w") as deploy, \
        open(source_key, "r") as key, \
        open(source_chain, "r") as chain:
    deploy.write(key.read())
    deploy.write(chain.read())

EO_LE_HARAKA_DEPLOY

	tee "$_deploy/deploy/haraka" <<'EO_LE_HARAKA_POST'
#!/bin/sh
jexec haraka service haraka restart
EO_LE_HARAKA_POST

	chmod 755 "$_deploy/deploy/haraka"
	chmod 755 "$_deploy/post/haraka"
}

install_deploy_scripts()
{
	tell_status "installing deployment scripts"
	export _deploy="/usr/local/etc/letsencrypt/renewal-hooks"

	install_deploy_haproxy
	install_deploy_dovecot
	install_deploy_haraka
}

update_haproxy_ssld()
{
	local _haconf="$ZFS_DATA_MNT/haproxy/etc/haproxy.conf"
	if ! grep -q 'ssl crt /etc' "$_haconf"; then
		# already updated
		return
	fi

	tell_status "switching haproxy TLS cert dir to /data/ssl.d"
	sed -i.bak \
		-e 's!ssl crt /etc.*!ssl crt /data/ssl.d!' \
		"$_haconf"
}

configure_certbot()
{
	install_deploy_scripts

	tell_status "configuring Certbot"

	local _HTTPDIR="$ZFS_DATA_MNT/webmail"
	local _certbot="/usr/local/bin/certbot"
	if $_certbot certonly --webroot-path "$_HTTPDIR" -d "$TOASTER_HOSTNAME"; then
		update_haproxy_ssld
		tell_status "renewing certs and installing with deployment scripts"
		certbot renew --force-renewal
	else
		tell_status "TLS Certificate Issue failed"
		exit 1
	fi
}

test_certbot()
{
	if [ ! -d "/usr/local/etc/letsencrypt" ]; then
		echo "not installed!"
		exit
	fi

	echo "it worked"
}

install_certbot
configure_certbot
test_certbot
