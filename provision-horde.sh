#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""
export JAIL_CONF_EXTRA="
        mount += \"$ZFS_DATA_MNT/horde \$path/data nullfs rw 0 0\";
        mount += \"$ZFS_DATA_MNT/vpopmail \$path/usr/local/vpopmail nullfs rw 0 0\";"

mt6-include 'php'
mt6-include nginx

install_horde()
{

    if [ ! -d "$ZFS_DATA_MNT/horde/data" ]; then
        tell_status "creating $ZFS_DATA_MNT/horde/data"
        mkdir "$ZFS_DATA_MNT/horde/data"
    fi

    tell_status "making vpopmail dir"
    mkdir -p "$STAGE_MNT/usr/local/vpopmail"  || exit

    install_php 56 || exit
	install_nginx || exit
    
	tell_status "installing Horde IMP and Ingo "
	stage_pkg_install horde-ingo
    stage_pkg_install horde-imp
    stage_pkg_install php56-simplexml php56-ftp php56-gd php56-fileinfo php56-tidy
    stage_pkg_install pecl-imagick
}

enable_ftp_server_ingo()
{
    tell_status "Making Ingo able to write maildrop mailfilter"
    stage_sysrc ftpd_enable=YES
    stage_exec pw groupadd -n vchkpw -g 89
    stage_exec pw useradd -n vpopmail -s /bin/sh -d /usr/local/vpopmail -u 89 -g 89 -m -h-
    stage_exec chpass -p $(openssl passwd -1 vpopmail) vpopmail
}

configure_nginx_server()
{
	local _datadir="$ZFS_DATA_MNT/horde"
	if [ -f "$_datadir/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tell_status "saving /data/etc/nginx-locations.conf"
	tee "$_datadir/etc/nginx-locations.conf" <<'EO_NGINX_SERVER'

server_name horde;

location /horde {
    root /usr/local/www/;
    index index.php index.html;

    try_files $uri $uri/ /rampage.php?$args;

    location ~ ^/horde/(.+\.php) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
        fastcgi_param PHP_VALUE "cgi.fix_pathinfo=1";
        fastcgi_pass php;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include        /usr/local/etc/nginx/fastcgi_params;
        root /usr/local/www/;
    }
    location ~ ^/horde/(.+\.(?:ico|css|js|gif|jpe?g|png))$ {
         root /usr/local/www/;
        expires max;
        add_header Pragma public;
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
    }

}
EO_NGINX_SERVER

}

install_horde_mysql()
{
	local _init_db=0
	if ! mysql_db_exists horde; then
		tell_status "creating horde mysql db"
		echo "CREATE DATABASE horde;" | jexec mysql /usr/local/bin/mysql || exit
		_init_db=1
	fi

	_hordepass=$(openssl rand -hex 18)

    _horde_key=$(openssl rand -hex 20)

	local _horde_dir="$STAGE_MNT/usr/local/www/horde/config"

	tee   "$_horde_dir/conf.php" << EO_HORDE_CONF
<?php

\$conf['vhosts'] = false;
\$conf['debug_level'] = E_ALL & ~E_NOTICE;
\$conf['max_exec_time'] = 0;
\$conf['compress_pages'] = true;
\$conf['secret_key'] = '$_horde_key';
\$conf['umask'] = 077;
\$conf['testdisable'] = true;
\$conf['use_ssl'] = 1;
\$conf['server']['name'] = '$TOASTER_HOSTNAME';
\$conf['urls']['token_lifetime'] = 30;
\$conf['urls']['hmac_lifetime'] = 30;
\$conf['urls']['pretty'] = false;
\$conf['safe_ips'] = array();
\$conf['session']['name'] = 'Horde';
\$conf['session']['use_only_cookies'] = true;
\$conf['session']['timeout'] = 0;
\$conf['session']['cache_limiter'] = 'nocache';
\$conf['session']['max_time'] = 72000;
\$conf['cookie']['domain'] = '$TOASTER_HOSTNAME';
\$conf['cookie']['path'] = '/horde';
\$conf['sql']['username'] = 'horde';
\$conf['sql']['password'] = '$_hordepass';
\$conf['sql']['hostspec'] = '$(get_jail_ip mysql)';
\$conf['sql']['port'] = 3306;
\$conf['sql']['protocol'] = 'tcp';
\$conf['sql']['database'] = 'horde';
\$conf['sql']['charset'] = 'utf-8';
\$conf['sql']['ssl'] = false;
\$conf['sql']['splitread'] = false;
\$conf['sql']['phptype'] = 'mysqli';
\$conf['nosql']['phptype'] = false;
\$conf['ldap']['useldap'] = false;
\$conf['auth']['admins'] = array('$TOASTER_ADMIN_EMAIL');
\$conf['auth']['checkip'] = true;
\$conf['auth']['checkbrowser'] = true;
\$conf['auth']['resetpassword'] = true;
\$conf['auth']['alternate_login'] = false;
\$conf['auth']['redirect_on_logout'] = false;
\$conf['auth']['list_users'] = 'list';
\$conf['auth']['params']['app'] = 'imp';
\$conf['auth']['driver'] = 'application';
\$conf['auth']['params']['count_bad_logins'] = false;
\$conf['auth']['params']['login_block'] = false;
\$conf['auth']['params']['login_block_count'] = 5;
\$conf['auth']['params']['login_block_time'] = 5;
\$conf['signup']['allow'] = false;
\$conf['log']['priority'] = 'INFO';
\$conf['log']['ident'] = 'HORDE';
\$conf['log']['name'] = LOG_USER;
\$conf['log']['type'] = 'syslog';
\$conf['log']['enabled'] = true;
\$conf['log_accesskeys'] = false;
\$conf['prefs']['maxsize'] = 65535;
\$conf['prefs']['params']['driverconfig'] = 'horde';
\$conf['prefs']['driver'] = 'Sql';
\$conf['alarms']['params']['driverconfig'] = 'horde';
\$conf['alarms']['params']['ttl'] = 300;
\$conf['alarms']['driver'] = 'Sql';
\$conf['group']['params']['driverconfig'] = 'horde';
\$conf['group']['driver'] = 'Sql';
\$conf['perms']['driverconfig'] = 'horde';
\$conf['perms']['driver'] = 'Sql';
\$conf['share']['no_sharing'] = false;
\$conf['share']['auto_create'] = true;
\$conf['share']['world'] = true;
\$conf['share']['any_group'] = false;
\$conf['share']['hidden'] = false;
\$conf['share']['cache'] = false;
\$conf['share']['driver'] = 'Sqlng';
\$conf['cache']['default_lifetime'] = 86400;
\$conf['cache']['params']['sub'] = 0;
\$conf['cache']['driver'] = 'File';
\$conf['cache']['use_memorycache'] = '';
\$conf['cachecssparams']['url_version_param'] = true;
\$conf['cachecss'] = false;
\$conf['cachejsparams']['url_version_param'] = true;
\$conf['cachejs'] = false;
\$conf['cachethemes'] = false;
\$conf['lock']['params']['driverconfig'] = 'horde';
\$conf['lock']['driver'] = 'Sql';
\$conf['token']['params']['driverconfig'] = 'horde';
\$conf['token']['driver'] = 'Sql';
\$conf['history']['params']['driverconfig'] = 'horde';
\$conf['history']['driver'] = 'Sql';
\$conf['davstorage']['params']['driverconfig'] = 'horde';
\$conf['davstorage']['driver'] = 'Sql';
\$conf['mailer']['params']['host'] = '$(get_jail_ip haraka)';
\$conf['mailer']['params']['port'] = 587;
\$conf['mailer']['params']['secure'] = 'tls';
\$conf['mailer']['params']['username_auth'] = true;
\$conf['mailer']['params']['password_auth'] = true;
\$conf['mailer']['params']['auth'] = true;
\$conf['mailer']['params']['lmtp'] = false;
\$conf['mailer']['type'] = 'smtp';
\$conf['vfs']['params']['driverconfig'] = 'horde';
\$conf['vfs']['type'] = 'Sql';
\$conf['sessionhandler']['type'] = 'Builtin';
\$conf['sessionhandler']['hashtable'] = false;
\$conf['spell']['driver'] = '';
\$conf['gnupg']['keyserver'] = array('pool.sks-keyservers.net');
\$conf['gnupg']['timeout'] = 10;
\$conf['nobase64_img'] = false;
\$conf['image']['driver'] = 'Imagick';
\$conf['exif']['driver'] = 'Bundled';
\$conf['timezone']['location'] = 'ftp://ftp.iana.org/tz/tzdata-latest.tar.gz';
\$conf['problems']['email'] = 'webmaster@example.com';
\$conf['problems']['maildomain'] = 'example.com';
\$conf['problems']['tickets'] = false;
\$conf['problems']['attachments'] = true;
\$conf['menu']['links']['help'] = 'all';
\$conf['menu']['links']['prefs'] = 'authenticated';
\$conf['menu']['links']['problem'] = 'all';
\$conf['menu']['links']['login'] = 'all';
\$conf['menu']['links']['logout'] = 'authenticated';
\$conf['portal']['fixed_blocks'] = array();
\$conf['accounts']['driver'] = 'null';
\$conf['user']['verify_from_addr'] = false;
\$conf['user']['select_view'] = true;
\$conf['facebook']['enabled'] = false;
\$conf['twitter']['enabled'] = false;
\$conf['urlshortener'] = false;
\$conf['weather']['provider'] = false;
\$conf['imap']['enabled'] = false;
\$conf['imsp']['enabled'] = false;
\$conf['kolab']['enabled'] = false;
\$conf['hashtable']['driver'] = 'none';
\$conf['activesync']['enabled'] = false;
/* CONFIG END. DO NOT CHANGE ANYTHING IN OR BEFORE THIS LINE. */

EO_HORDE_CONF

tee  -a "$_horde_dir/prefs.php" << 'EO_HORDE_PREFS'
$_prefs['initial_application']['value'] = 'imp';
EO_HORDE_PREFS



	if [ "$_init_db" = "1" ]; then
		tell_status "configuring horde mysql permissions"
		local _grant='GRANT ALL PRIVILEGES ON horde.* to'

		echo "$_grant 'horde'@'$(get_jail_ip horde)' IDENTIFIED BY '${_hordepass}';" \
			| jexec mysql /usr/local/bin/mysql || exit

		echo "$_grant 'horde'@'$(get_jail_ip stage)' IDENTIFIED BY '${_hordepass}';" \
			| jexec mysql /usr/local/bin/mysql || exit
		horde_init_db
	fi
}

horde_init_db()
{
	tell_status "initializating Horde db"
	#pkg install -y curl || exit
	#start_roundcube
	#curl -i -F initdb='Initialize database' -XPOST \
    #		"http://$(get_jail_ip stage)/installer/index.php?_step=3" || exit
}

configure_horde_imp()
{
    tell_status "initializating Horde IMP config"

    local _horde_imp_dir="$STAGE_MNT/usr/local/www/horde/imp/config"

tee  "$_horde_imp_dir/conf.php" << 'EO_HORDE_IMP_CONF'
<?php
/* CONFIG START. DO NOT CHANGE ANYTHING IN OR AFTER THIS LINE. */
// $Id: 48bf0b4cc99e7941b4432a29e70e145b8d654cc7 $
$conf['user']['allow_view_source'] = true;
$conf['server']['server_list'] = 'none';
$conf['compose']['use_vfs'] = false;
$conf['compose']['link_attachments_notify'] = true;
$conf['compose']['link_attach_threshold'] = 5242880;
$conf['compose']['link_attach_size_limit'] = 0;
$conf['compose']['link_attach_size_hard'] = 0;
$conf['compose']['link_attachments'] = true;
$conf['compose']['attach_size_limit'] = 0;
$conf['compose']['attach_count_limit'] = 0;
$conf['compose']['reply_limit'] = 200000;
$conf['compose']['ac_threshold'] = 3;
$conf['compose']['htmlsig_img_size'] = 30000;
$conf['pgp']['keylength'] = 1024;
$conf['maillog']['driver'] = 'history';
$conf['sentmail']['driver'] = 'Null';
$conf['contactsimage']['backends'] = array('IMP_Contacts_Avatar_Addressbook');
$conf['tasklist']['use_tasklist'] = true;
$conf['notepad']['use_notepad'] = true;
/* CONFIG END. DO NOT CHANGE ANYTHING IN OR BEFORE THIS LINE. */
EO_HORDE_IMP_CONF

    local _horde_imp_backend="$STAGE_MNT/usr/local/www/horde/imp/config/backends.local.php"
	cp "$STAGE_MNT/usr/local/www/horde/imp/config/backends.php" $_horde_imp_backend
    sed -i .bak \
		-e "s/'hostspec' => 'localhost'/'hostspec' => '$(get_jail_ip dovecot)'/" \
		"$_horde_imp_backend" || exit
}

configure_horde_ingo()
{
    local _horde_ingo="$STAGE_MNT/usr/local/www/horde/ingo/config"

tee "$_horde_ingo/conf.php" << 'EO_INGO_CONF'
<?php
/* CONFIG START. DO NOT CHANGE ANYTHING IN OR AFTER THIS LINE. */
// $Id: 48142d13ef06c07f56427fe5b43981631bdbfdb0 $
$conf['storage']['params']['driverconfig'] = 'horde';
$conf['storage']['driver'] = 'sql';
$conf['rules']['userheader'] = true;
$conf['spam']['header'] = 'X-Spam-Level';
$conf['spam']['char'] = '*';
$conf['spam']['compare'] = 'string';
/* CONFIG END. DO NOT CHANGE ANYTHING IN OR BEFORE THIS LINE. */
EO_INGO_CONF

tee "$_horde_ingo/hooks.php" << 'EO_INGO_HOOKS'
<?php
class Ingo_Hooks
{
    /**
     * Returns the username/password needed to connect to the transport
     * backend.
     *
     * @param string $driver  The driver name (array key from backends.php).
     *
     * @return mixed  If non-array, uses Horde authentication credentials
                      (DEFAULT). Otherwise, an array with the following keys
     *                (non-existent keys will use default values):
     *  - euser: (string; SIEVE ONLY) For the sieve driver, the effective
     *           user to use.
     *  - password: (string) Password.
     *  - username: (string) User name.
     */
    public function transport_auth($driver)
    {
        //switch ($driver) {
        //case 'maildrop':
            return array(
                'password' => 'vpopmail',
                'username' => 'vpopmail'
            );
    	}
}
EO_INGO_HOOKS


	tee "$_horde_ingo/backends.local.php" << EO_INGO_BACKEND
<?php

/* IMAP Example */
\$backends['imap']['disabled'] = true;

/* Maildrop Example */
\$backends['maildrop'] = array(
    // Disabled by default
    'disabled' => false,
    'transport' => array(
        Ingo::RULE_ALL => array(
            'driver' => 'vfs',
            'params' => array(
                'hostspec' => '$(get_jail_ip horde)',
                'filename' => '.mailfilter',
                'vfs_path' => '/usr/local/vpopmail/domains/%d/%f/Maildir',
                'vfstype' => 'ftp',
                'file_perms' => '0640',
            )
        ),
    ),
    'script' => array(
        Ingo::RULE_ALL => array(
            'driver' => 'maildrop',
            'params' => array(
                // added with Maildrop 2.5.1/Courier 0.65.1.
                'mailbotargs' => '-N',
                'path_style' => 'maildir',
                'strip_inbox' => false,
                'variables' => array(
                    // 'PATH' => '/usr/bin'
                        'SHELL' => '"/bin/sh"
                        import EXT
                        import HOST',
                        'VPOP' => '"| /usr/local/vpopmail/bin/vdelivermail \'\' bounce-no-mailbox"',
                        'VHOME' => '\`pwd\`',
                        'HOME' => '\`pwd\`',
                        'DEFAULT' => '\$VHOME/Maildir'
                    )
            ),
        ),
    ),
    'shares' => false
);

/* Procmail Example */
\$backends['procmail']['disabled'] = true;
/* Sieve Example */
\$backends['sieve']['disabled'] = true;
/* sivtest Example */
\$backends['sivtest']['disabled'] = true;
/* Sun ONE/JES Example (LDAP/Sieve) */
\$backends['ldapsieve']['disabled'] = true;
/* ISPConfig Example */
\$backends['ispconfig']['disabled'] = true;
/* Custom SQL Example */
\$backends['customsql']['disabled'] = true;
?>
EO_INGO_BACKEND


}

install_default_horde_conf()
{

	local _local_config_horde="$ZFS_JAIL_MNT/horde/usr/local/www/horde/config/conf.php"
	local _horde_install="$ZFS_JAIL_MNT/horde/usr/local/www/horde"
	local _horde_stage="$STAGE_MNT/usr/local/www/horde"


	if [ -f "$_local_config_horde" ]; then
		#Assuming if Horde is configured IMP and Ingo will be as well
		tell_status "preserving horde configuration.php"
		cp "$_horde_install/config/conf.php" "$STAGE_MNT/usr/local/www/horde/config/" || exit
		cp "$_horde_install/config/prefs.php" "$STAGE_MNT/usr/local/www/horde/config/" || exit
		cp "$_horde_install/imp/config/conf.php" "$STAGE_MNT/usr/local/www/horde/imp/config/" || exit
		cp "$_horde_install/imp/config/backends.local.php" "$STAGE_MNT/usr/local/www/horde/imp/config/" || exit
		cp "$_horde_install/ingo/config/conf.php" "$STAGE_MNT/usr/local/www/horde/ingo/config/" || exit
		cp "$_horde_install/ingo/config/backends.local.php" "$STAGE_MNT/usr/local/www/horde/ingo/config/" || exit
		cp "$_horde_install/ingo/config/hooks.php" "$STAGE_MNT/usr/local/www/horde/ingo/config/" || exit
		return
	else
		tell_status "creating Mysql Database"
		install_horde_mysql
		configure_horde_imp
        configure_horde_ingo
		tell_status "post-install configuration will be required"
		sleep 2
	fi

}

configure_horde()
{
	configure_php horde
	configure_nginx horde
	configure_nginx_server

	install_default_horde_conf

    enable_ftp_server_ingo
    tell_status "Get Vfs patch"
    fetch -o "$STAGE_MNT/usr/local/www/horde/ingo/lib/Transport/Vfs.php" \
        "https://raw.githubusercontent.com/Infern1/horde/19e926cab5e1a34f9db8ffffdc55fb37235d4869/ingo/lib/Transport/Vfs.php" || exit

	# for persistent data storage
	chown 80:80 "$ZFS_DATA_MNT/horde/"
	chown -R 80:80 "$STAGE_MNT/usr/local/www/horde/"

	#set_default_path
	#install_default_ini
}

start_horde()
{
	stage_exec service ftpd start || exit
    start_php_fpm
	start_nginx
    stage_exec /usr/local/bin/horde-db-migrate || exit
}

test_horde()
{
	test_nginx
	test_php_fpm
    stage_listening 21
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs horde
start_staged_jail horde
install_horde
configure_horde
start_horde
test_horde
promote_staged_jail horde
