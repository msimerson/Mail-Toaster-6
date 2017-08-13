#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# https://wiki.freebsd.org/Docker
# https://docs.gitlab.com/runner/install/freebsd.html
install_glr_rcd()
{
	if [ ! -d "$STAGE_MNT//usr/local/etc/rc.d" ]; then
		mkdir -p "$STAGE_MNT/usr/local/etc/rc.d"
	fi

	tee "$STAGE_MNT//usr/local/etc/rc.d/gitlab_runner" << 'EOGLRC'
#!/bin/sh
# PROVIDE: gitlab_runner
# REQUIRE: DAEMON NETWORKING
# BEFORE:
# KEYWORD:

. /etc/rc.subr

name="gitlab_runner"
rcvar="gitlab_runner_enable"

load_rc_config $name

user="gitlab-runner"
user_home="/home/gitlab-runner"
command="/usr/local/bin/gitlab-runner run"
pidfile="/var/run/${name}.pid"

start_cmd="gitlab_runner_start"
stop_cmd="gitlab_runner_stop"
status_cmd="gitlab_runner_status"

gitlab_runner_start()
{
    export USER=${user}
    export HOME=${user_home}
    if checkyesno ${rcvar}; then
        cd ${user_home}
        /usr/sbin/daemon -u ${user} -p ${pidfile} ${command} > /var/log/gitlab_runner.log 2>&1
    fi
}

gitlab_runner_stop()
{
    if [ -f ${pidfile} ]; then
        kill `cat ${pidfile}`
    fi
}

gitlab_runner_status()
{
    if [ ! -f ${pidfile} ] || kill -0 `cat ${pidfile}`; then
        echo "Service ${name} is not running."
    else
        echo "${name} appears to be running."
    fi
}

run_rc_command $1
EOGLRC

    chmod +x "$STAGE_MNT/usr/local/etc/rc.d/gitlab_runner"
}

install_gitlab_runner()
{
	tell_status "installing GitLab Runner!"
	stage_exec pw group add -n gitlab-runner -m
	stage_exec pw user add -n gitlab-runner -g gitlab-runner -s /usr/local/bin/bash
	#stage_exec mkdir /home/gitlab-runner
	#stage_exec chown gitlab-runner:gitlab-runner /home/gitlab-runner
	stage_exec fetch -m -o /usr/local/bin/gitlab-runner https://gitlab-ci-multi-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-ci-multi-runner-freebsd-amd64
	stage_exec chmod +x /usr/local/bin/gitlab-runner
	stage_exec touch /var/log/gitlab_runner.log && chown gitlab-runner:gitlab-runner /var/log/gitlab_runner.log
    install_glr_rcd
}

configure_gitlab_runner()
{
	tell_status "configuring GitLab Runner!"
	stage_sysrc "gitlab_runner_enable=YES"
}

start_gitlab_runner()
{
	tell_status "starting up GitLab Runner!"
	stage_exec service gitlab_runner start
}

test_gitlab_runner()
{
	tell_status "testing nothing!"

	echo "it worked"
}

base_snapshot_exists || exit
create_staged_fs gitlab_runner
start_staged_jail gitlab_runner
install_gitlab_runner
configure_gitlab_runner
start_gitlab_runner
test_gitlab_runner
promote_staged_jail gitlab_runner
