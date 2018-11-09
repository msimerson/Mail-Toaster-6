#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
# shellcheck disable=2016
export JAIL_CONF_EXTRA=""

mt6-include 'php'
mt6-include nginx

install_drupal()
{
	assure_jail mysql

	tell_status "installing Drupal 8"
	stage_pkg_install drupal8

	install_nginx || exit
}

configure_nginx_server()
{
	if [ -f "$STAGE_MNT/data/etc/nginx-locations.conf" ]; then
		tell_status "preserving /data/etc/nginx-locations.conf"
		return
	fi

	tee "$STAGE_MNT/data/etc/nginx-locations.conf" <<'EO_DRUPAL_NGINX'

	root   /usr/local/www/drupal8;

	location / {
	    index  index.php;
	}

	location ~ \.php$ {
		# try_files $uri =404;
		include        /usr/local/etc/nginx/fastcgi_params;
		fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		fastcgi_pass php;
	}

	location ~* \.(?:css|gif|htc|ico|js|jpe?g|png|swf)$ {
		expires max;
		log_not_found off;
	}

EO_DRUPAL_NGINX

}

configure_drupal()
{
	configure_php drupal
	configure_nginx drupal
	configure_nginx_server

# mkdir sites/default/files
# cp sites/default/default.settings.php sites/default/settings.php
# chown -R www:www sites/default/settings.php
# GRANT ALL PRIVILEGES ON tnpi_drupal.* TO 'tnpidrupal'@'172.16.15.%' IDENTIFIED BY 'kungeo85_Twistnat';
# pkg install git-lite php72-bcmath php72-curl php72-xmlwriter composer-php72 drush-php72
# drush archive-dump
# drush ups && drush sset system.maintenance_mode 1 && drush cr
# drush up drupal  (or drush up --security-only)
# drush updatedb
# composer require "drupal/commerce"
# composer update drupal/core --with-dependencies
# composer require drupal/console:~1.0 --prefer-dist --optimize-autoloader

	_htdocs="$STAGE_MNT/usr/local/www/drupal"

	if [ -f "$ZFS_JAIL_MNT/drupal/usr/local/www/drupal8/configuration.php" ]; then
		echo "preserving drupal configuration.php"
		cp "$ZFS_JAIL_MNT/drupal/usr/local/www/drupal8/configuration.php" "$_htdocs/"
		return
	fi

	if [ ! -f "$_htdocs/robots.txt" ]; then
		tell_status "installing robots.txt"
		tee "$_htdocs/robots.txt" <<EO_ROBOTS_TXT
User-agent: *
Disallow: /
EO_ROBOTS_TXT
	fi
}

start_drupal()
{
	start_php_fpm
	start_nginx
}

test_drupal()
{
	test_php_fpm
	test_nginx
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs drupal
start_staged_jail drupal
install_drupal
configure_drupal
start_drupal
test_drupal
promote_staged_jail drupal
