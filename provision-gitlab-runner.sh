#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

# https://wiki.freebsd.org/Docker
# https://docs.gitlab.com/runner/install/freebsd.html

install_gitlab_runner_pkg()
{
	tell_status "installing GitLab Runner package"
	stage_pkg_install gitlab-runner
}

install_gitlab_runner_port()
{
	tell_status "installing GitLab Runner port"
	stage_pkg_install dialog4ports go
	stage_port_install devel/gitlab-runner || exit
}

install_gitlab_runner_latest()
{
	tell_status "installing GitLab Runner Latest"
	stage_exec fetch -m -o /usr/local/bin/gitlab-runner https://gitlab-ci-multi-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-ci-multi-runner-freebsd-amd64
	stage_exec chmod +x /usr/local/bin/gitlab-runner
}

install_docker_freebsd()
{
	# argggg, never mind. After getting FreeBSD up and running inside
	# a Docker, I realize that Docker work work for my purposes because
	# there's no ZFS pools mounted inside the docker
	pkg install docker-freebsd
	zfs create -o mountpoint=/usr/docker zroot/docker
	pw groupadd docker
	pw usermod gitlab-runner -G docker
	#proc                /proc           procfs  rw,noauto       0       0
	#mount /proc
	#docker run -it auchida/freebsd /bin/sh
	sysrc docker_enable=YES
	service docker start
}

install_gitlab_runner()
{
	tell_status "setting up gitlab-runner user"
	stage_exec pw group add -n gitlab-runner -m
	stage_exec pw user add -n gitlab-runner -g gitlab-runner -s /usr/local/bin/bash
	stage_exec mkdir /home/gitlab-runner
	stage_exec chown gitlab-runner:gitlab-runner /home/gitlab-runner
	touch "$STAGE_MNT/var/log/gitlab_runner.log"
	stage_exec chown gitlab-runner:gitlab-runner /var/log/gitlab_runner.log

	install_gitlab_runner_pkg
	# Version:      1.11.1
	# Git revision: 08a9e6f
	# Git branch:   9-0-stable

	install_gitlab_runner_port
	# Version:      9.3.0
	# Git revision: 3df822b
	# Git branch:   9-3-stable

	# install_gitlab_runner_latest
	# Version:      9.4.2
	# Git revision: 6d06f2e
	# Git branch:   9-4-stable
}

configure_gitlab_runner()
{
	tell_status "configuring GitLab Runner!"
	stage_sysrc gitlab_runner_enable=YES
	stage_sysrc gitlab_runner_dir=/home/gitlab-runner
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
