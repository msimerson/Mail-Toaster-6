#!/bin/sh

. mail-toaster.sh || exit

export JAIL_CONF_EXTRA="
        mount += \"$ZFS_DATA_MNT/redis \$path/data nullfs rw 0 0\";"

install_redis()
{
    tell_status "installing redis"
	stage_pkg_install redis || exit
}

configure_redis()
{
    tell_status "configuring redis"

    mkdir -p $STAGE_MNT/data/db $STAGE_MNT/data/log \
        $STAGE_MNT/usr/local/etc/newsyslog.conf.d || exit
    stage_exec chown redis:redis /data/db /data/log || exit

    local _redis_etc="$STAGE_MNT/usr/local/etc/redis.conf"
    # sed -i -e 's/^# syslog-enabled no/syslog-enabled yes/' $_redis_etc
    sed -i -e 's/^stop-writes-on-bgsave-error yes/stop-writes-on-bgsave-error no/' $_redis_etc
    sed -i -e 's/^dir \/var\/db\/redis\//dir \/data\/db\//' $_redis_etc
    sed -i -e 's/^logfile .*/logfile \/data\/log\/redis.log/' $_redis_etc

	echo '/data/log/redis.log   redis:redis 644  7  *  @T00   JC   /var/run/redis/redis.pid' \
   		> $STAGE_MNT/usr/local/etc/newsyslog.conf.d/redis
}

start_redis()
{
    tell_status "starting redis"
	stage_sysrc redis_enable=YES
	stage_exec service redis start
}

test_redis()
{
	echo "testing redis..."
	stage_exec sockstat -l -4 | grep 6379 || exit
}

base_snapshot_exists \
	|| (echo "$BASE_SNAP must exist, use provision-base.sh to create it" \
	&& exit)

create_data_fs redis
create_staged_fs redis
stage_sysrc hostname=redis
start_staged_jail
install_redis
configure_redis
start_redis
test_redis
promote_staged_jail redis
