#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# https://github.com/gitlabhq/gitlab-recipes/blob/master/install/freebsd/freebsd-10.md
# https://github.com/t-zuehlsdorff/gitlabhq/blob/master/doc/install/installation-freebsd.md
# http://gitlab.toco-domains.de/FreeBSD/GitLab-docu/blob/master/install/9.1-freebsd.md

install_redis()
{
	tell_status "configuring Redis"

	tee -a "$STAGE_MNT/usr/local/etc/redis.conf" <<EO_SOCKET
unixsocket /var/run/redis/redis.sock
unixsocketperm 770
EO_SOCKET
	stage_sysrc redis_enable=YES
	stage_exec pw groupmod redis -m git
	stage_exec service redis restart
}

install_postgresl()
{
	tell_status "installing PostgresQL server 9.5!"
	# /etc/sysctl.conf: security.jail.sysvipc_allowed=1 
	# jail.conf: allow.sysvipc=1

	if ! grep -q ^postgres "$STAGE/etc/login.conf"; then
		tee -a "$STAGE/etc/login.conf" <<EO_LC
postgres:\
		:lang=en_US.UTF-8:\
		:setenv=LC_COLLATE=C:\
		:tc=default:
EO_LC

 		stage_exec cap_mkdb /etc/login.conf
		stage_sysrc postgresql_class=postgres
	fi

	stage_pkg_install postgresql95-server postgresql95-contrib
	stage_sysrc postgresql_enable=YES
	stage_exec service postgresql initdb
	stage_exec service postgresql start
	psql -d template1 -U pgsql -c "CREATE USER git CREATEDB SUPERUSER;"
	psql -d template1 -U pgsql -c "CREATE DATABASE gitlabhq_production OWNER git;"
	psql -U pgsql -d gitlabhq_production -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
}

install_nginx()
{
	tell_status "installing nginx!"
	stage_pkg_install nginx
	mkdir "$STAGE_MNT/var/log/nginx"
	stage_syrc nginx_enable=YES
}

install_gitlab()
{
	tell_status "installing GitLab!"
	stage_exec pkg install -y gitlab nginx

	install_postgresql
	install_redis
}

configure_gitlab()
{
	tell_status "configuring GitLab!"
	stage_exec pw usermod git -d /home/git -m
	stage_exec su -l git -c "git config --global core.autocrlf input"
	stage_exec su -l git -c "git config --global gc.auto 0"
	stage_exec su -l git -c "git config --global repack.writeBitmaps true"
	stage_exec su -l git -c "mkdir -p /home/git/.ssh"

	if [ -d "$STAGE_MNT/usr/home" ]; then
		rm -r "STAGE_MNT/usr/home"
		stage_exec ln -s /home /usr/home
	fi

	chown root /usr/local/share/gitlab-shell
	su -l git -c "cd /usr/local/www/gitlab && rake gitlab:setup RAILS_ENV=production"
	chown root /usr/local/share/gitlab-shell

	stage_sysrc gitlab_enable=YES
}

start_gitlab()
{
	tell_status "starting up GitLab!"
	stage_exec su -l git -c "cd /usr/local/www/gitlab && rake yarn:install gitlab:assets:clean gitlab:assets:compile RAILS_ENV=production NODE_ENV=production"
	psql -d template1 -U pgsql -c "ALTER USER git WITH NOSUPERUSER;"
	stage_exec service gitlab start
}

test_gitlab()
{
	tell_status "testing GitLab!"

	su -l git -c "cd /usr/local/www/gitlab && rake gitlab:env:info RAILS_ENV=production"
	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs gitlab
start_staged_jail gitlab
install_gitlab
configure_gitlab
start_gitlab
test_gitlab
promote_staged_jail gitlab
