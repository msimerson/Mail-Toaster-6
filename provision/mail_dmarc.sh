#!/bin/sh

set -e -u

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""
export JAIL_FSTAB=""

install_dmarc()
{
	tell_status "installing Mail::DMARC deps"
	stage_pkg_install perl5 p5-File-ShareDir p5-Module-Build p5-XML-LibXML p5-Regexp-Common
	stage_pkg_install p5-Net-DNS p5-Net-IP p5-Net-Server p5-Net-SMTPS p5-Net-IDN-Encode p5-Mail-DKIM
	stage_pkg_install p5-Email-MIME p5-Email-Simple p5-Net-IMAP-Simple p5-Email-Sender
	stage_pkg_install p5-CGI p5-HTTP-Tiny p5-libwww p5-HTTP-Date p5-JSON p5-HTTP-Message p5-URI
	stage_pkg_install p5-Test-Output p5-Test-File-ShareDir p5-Test-Exception p5-Net-DNS-Resolver-Mock
	stage_pkg_install p5-Config-Tiny p5-DBIx-Simple p5-DBD-mysql
	stage_pkg_install p5-Mail-DMARC

	tell_status "installing Mail::DMARC from CPAN"
	stage_exec perl -MCPAN -e 'install Mail::DMARC'

	tell_status "Mail::DMARC installed"

	store_exec "$STAGE_MNT/usr/local/etc/periodic/daily/dmarc_receive" <<EO_DMARC
#!/bin/sh
/usr/local/bin/dmarc_receive --imap
EO_DMARC

	install_dmarc_config
}

install_dmarc_config()
{
	local _data_cf="$ZFS_DATA_MNT/mail-dmarc.ini"
	if [ -f "$_data_cf" ]; then
		tell_status "preserving $_data_cf"
	else
		tell_status "installing default mail-dmarc.ini"
		cp "$STAGE_MNT/usr/local/lib/perl5/site_perl/auto/share/dist/Mail-DMARC/mail-dmarc.ini" "$_data_cf"
	fi

	stage_exec ln -s /data/mail-dmarc.ini /etc/mail-dmarc.ini
}

start_dmarc()
{
	tell_status "starting Mail::DMARC httpd service"
	stage_exec /usr/local/bin/dmarc_httpd &

	echo "/usr/local/bin/dmarc_httpd &" >> "$STAGE_MNT/etc/rc.local"
	sleep 1
}

test_dmarc()
{
	stage_listening 8080
	sleep 1
}

base_snapshot_exists || exit
create_staged_fs mail_dmarc
start_staged_jail mail_dmarc
install_dmarc
start_dmarc
test_dmarc
promote_staged_jail mail_dmarc
