#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_redis()
{
	tell_status "installing redis"
	stage_pkg_install redis || exit
}

configure_redis()
{
	tell_status "configuring redis"

	for _dir in db log etc; do
		mkdir -p "$STAGE_MNT/data/$_dir" || exit
	done

	mkdir -p "$STAGE_MNT/usr/local/etc/newsyslog.conf.d" || exit
	stage_exec chown redis:redis /data/db /data/log /data/etc || exit

	sed -i .bak \
		-e '/^stop-writes-on-bgsave-error/ s/yes/no/' \
		-e 's/^dir \/var\/db\/redis\//dir \/data\/db\//' \
		-e 's/^# syslog-enabled no/syslog-enabled yes/' \
		-e 's/^logfile .*/logfile \/data\/log\/redis.log/' \
		-e 's/^bind.*/#&/' \
		-e '/^protected-mode/ s/yes/no/' \
		"$STAGE_MNT/usr/local/etc/redis.conf"

	echo '/data/log/redis.log   redis:redis 644  7  *  @T00   JC   /var/run/redis/redis.pid' \
   		> "$STAGE_MNT/usr/local/etc/newsyslog.conf.d/redis"
}

start_redis()
{
	tell_status "starting redis"
	stage_sysrc redis_enable=YES
	stage_exec service redis start
}

test_redis()
{
	echo "testing redis"
	stage_listening 6379 3 2
}

base_snapshot_exists || exit
create_staged_fs redis
start_staged_jail redis
install_redis
configure_redis
start_redis
test_redis
promote_staged_jail redis
