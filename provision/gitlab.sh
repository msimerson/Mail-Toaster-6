#!/bin/sh

. mail-toaster.sh || exit

export JAIL_START_EXTRA="allow.sysvipc=1"
export JAIL_CONF_EXTRA="
		allow.sysvipc;
"
export JAIL_FSTAB=""

# https://docs.gitlab.com/ee/install/relative_url.html
# https://gitlab.fechner.net/mfechner/Gitlab-docu/blob/master/install/15.10-freebsd.md
# https://github.com/gitlabhq/gitlab-recipes/blob/master/install/freebsd/freebsd-10.md

install_gitlab()
{
	tell_status "installing PostgresQL, Redis, and nginx"
	stage_pkg_install postgresql13-server postgresql13-contrib redis nginx || exit 1

	tell_status "installing GitLab"
	stage_exec pkg install -y gitlab-ce || exit 1
}

configure_nginx()
{
	tell_status "configuring nginx!"
	if [ ! -d "$STAGE_MNT/var/log/nginx" ]; then
		mkdir "$STAGE_MNT/var/log/nginx" || exit 1
		chown 80:80 "$STAGE_MNT/var/log/nginx"  || exit 1
	fi

	sed -i '' \
		-e '/http {/a\
    include       /usr/local/www/gitlab-ce/lib/support/nginx/gitlab;
'	"$STAGE_MNT/usr/local/etc/nginx/nginx.conf"

	stage_sysrc nginx_enable=YES
}

configure_postgres()
{
	tell_status "Configuring postgres"

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

	stage_sysrc postgresql_enable=YES
	stage_exec service postgresql initdb || exit 1

	tee -a "$STAGE_MNT/var/db/postgres/data13/pg_hba.conf" <<EO_PG_HBA
host	all		all		172.16.15.46/32		trust
host	all		all		172.16.15.254/32		trust
EO_PG_HBA

	stage_exec service postgresql start  || exit 1
	stage_exec psql -U postgres -d template1 -c "CREATE USER git CREATEDB SUPERUSER;"
	stage_exec psql -U postgres -d template1 -c "CREATE DATABASE gitlabhq_production OWNER git;"
	stage_exec psql -U postgres -d template1 -c "ALTER ROLE git WITH PASSWORD 'secure password';"
	stage_exec psql -U postgres -d gitlabhq_production -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
	stage_exec psql -U postgres -d gitlabhq_production -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"
}

configure_redis()
{
	tell_status "configuring Redis"
	tee -a "$STAGE_MNT/usr/local/etc/redis.conf" <<EO_SOCKET
unixsocket /var/run/redis/redis.sock
unixsocketperm 770
EO_SOCKET

	stage_exec pw groupmod redis -m git
	stage_sysrc redis_enable=YES
	stage_exec service redis start
}

configure_gitlab()
{
	configure_nginx
	configure_postgres
	configure_redis

		# -e '/path: / s/\/usr\/local/\/data/' \
	sed -i '' \
		-e "/[[:space:]]host:/ s/localhost/${TOASTER_HOSTNAME}/" \
		-e "/email_from:/ s/example@example.com/${TOASTER_ADMIN_EMAIL}/" \
		-e '/# relative_url_root/ s/# //' \
		"$STAGE_MNT/usr/local/www/gitlab-ce/config/gitlab.yml" || exit 1

# 	tee -a "$STAGE_MNT/usr/local/www/gitlab-ce/config/puma.rb" <<EO_REL
#   ENV['RAILS_RELATIVE_URL_ROOT'] = "/gitlab"
# EO_REL

	sed -i '' \
		-e '/gitlab_relative_url_root:/ s/# //; s/\//\/gitlab/' \
		"$STAGE_MNT/usr/local/share/gitlab-shell/config.yml"

	stage_exec cp /usr/local/www/gitlab-ce/config/initializers/relative_url.rb.example \
		/usr/local/www/gitlab-ce/config/initializers/relative_url.rb

	# stage_exec pw usermod git -d /data/git -m
	stage_exec su -l git -c "git config --global core.autocrlf input"
	stage_exec su -l git -c "git config --global gc.auto 0"
	stage_exec su -l git -c "git config --global repack.writeBitmaps true"
	stage_exec su -l git -c "git config --global receive.advertisePushOptions true"
	stage_exec su -l git -c "mkdir -p /usr/local/git/.ssh"
	stage_exec su -l git -c "mkdir -p /usr/local/git/repositories"
	stage_exec su -l git -c "chown -R git:git /usr/local/git"
	stage_exec su -l git -c "chmod 2770 /usr/local/git/repositories"

	tell_status "configuring GitLab!"
	stage_exec chown git /usr/local/share/gitlab-shell
	stage_exec su -l git -c "cd /usr/local/www/gitlab-ce && rake gitlab:setup RAILS_ENV=production"
	stage_exec chown root /usr/local/share/gitlab-shell

	stage_sysrc gitlab_enable=YES
	stage_sysrc gitlab_workhorse_options="-authBackend http://172.16.15.46:80/gitlab"
}

start_gitlab()
{
	tell_status "starting up GitLab"
	stage_exec su -l git -c "cd /usr/local/www/gitlab-ce && rake yarn:install gitlab:assets:clean gitlab:assets:compile RAILS_ENV=production NODE_ENV=production"
	stage_exec psql -U postgres -d template1 -c "ALTER USER git WITH NOSUPERUSER;"
	stage_exec service gitlab start
}

test_gitlab()
{
	tell_status "testing GitLab"

	stage_exec su -l git -c "cd /usr/local/www/gitlab-ce && rake gitlab:env:info RAILS_ENV=production"
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
