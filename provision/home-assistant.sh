#!/bin/sh

set -e

. mail-toaster.sh

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA="
                allow.raw_sockets;
		allow.sysvipc;
"
export JAIL_FSTAB=""

_ha_uid="8123"

install_homeassistant()
{
	tell_status "install Home Assistant dependencies"

	stage_pkg_install tmux git-lite ca_root_nss cmake ffmpeg gcc gmake libjpeg-turbo nasm openblas openjpeg pkgconf sqlite3 sudo
	stage_pkg_install rust pyenv python313

	stage_exec pw groupadd -n homeassistant -g $_ha_uid
	stage_exec pw useradd -n homeassistant -g homeassistant -u $_ha_uid -s /usr/local/bin/bash -w no -d /data/home/homeassistant -m -M 750 -G wheel

	install_ha_python
	install_hass
}

install_ha_python()
{
	tell_status "Installing Python 3.13.11 Virtual Environment"

	store_exec "/data/homeassistant/pyenv-setup.sh" <<'EO_PYENV'
#!/usr/local/bin/bash
set -e
if [ ! -d "$HOME/.pyenv/versions/3.13.11" ]; then pyenv install 3.13.11; fi
pyenv global 3.13.11
pyenv init || echo ''

if ! grep -q PYENV_ROOT "$HOME/.profile"; then
	tee -a "$HOME/.profile" <<EO_PROFILE

export PYENV_ROOT="\$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="\$PYENV_ROOT/bin:\$PATH"
eval "\$(pyenv init -)"

EO_PROFILE
fi

EO_PYENV

	stage_exec su -l homeassistant -c "/data/pyenv-setup.sh"
	stage_exec su -l homeassistant -c "python --version"
}

install_hass()
{
	_ha_ver="2026.1"
	tell_status "Installing Home Assistant $_ha_ver"

	mkdir -p "/data/homeassistant/home/homeassistant/HA-$_ha_ver"
	chown $_ha_uid:$_ha_uid "/data/homeassistant/home/homeassistant/HA-$_ha_ver"
	store_exec "/data/homeassistant/install-venv.sh" <<EOF
#!/usr/local/bin/bash

set -e

cd ~/HA-$_ha_ver
python -m venv .
source bin/activate
pip install --upgrade pip
pip install --upgrade wheel
pip install mutagen

mkdir -p ~/src
cd ~/src
if [ ! -d python-isal ]; then git clone https://github.com/pycompression/python-isal.git; fi
cd python-isal
git submodule update --init --recursive
pip install .

cd ~/src
pip install git+https://github.com/rhasspy/webrtc-noise-gain.git

cd ~/src
if [ ! -d numpy ]; then git clone https://github.com/numpy/numpy.git; fi
cd numpy
pip install .

cd ~/
pip install homeassistant~=$_ha_ver

EOF

	chown $_ha_uid:$_ha_uid "/data/homeassistant/install-venv.sh"
	stage_exec su -l homeassistant -c "/data/install-venv.sh"
}

configure_homeassistant()
{
	tell_status "configuring homeassistant"
	store_exec "/usr/local/etc/rc.d/homeassistant" <<'EO_RC'
#!/bin/sh
#
# https://github.com/tprelog/iocage-homeassistant/blob/master/overlay/usr/local/etc/rc.d/homeassistant
# 
# PROVIDE: homeassistant
# REQUIRE: LOGIN
# KEYWORD: shutdown
#
# homeassistant_user: The user account used to run the homeassistant daemon.
#       This is optional, however do not specifically set this to an
#       empty string as this will cause the daemon to run as root.
#       Default:  "homeassistant"
#
# homeassistant_group: The group account used to run the homeassistant daemon.
#       Default:  "homeassistant"
#
# homeassistant_config_dir: Directory where the homeassistant `configuration.yaml` is located.
#       Default:   "$HOME/.homeassistant"
#       Change:    `sysrc homeassistant_config_dir="/usr/local/etc/homeassistant"`
#
# homeassistant_venv: Directory where the homeassistant virtualenv is located.
#       Default:  "/usr/local/share/homeassistant"
#       Change:    `sysrc homeassistant_venv="/srv/homeassistant"`
#       Reset to default: `sysrc -x homeassistant_venv`

. /etc/rc.subr
name=homeassistant
rcvar=${name}_enable

pidfile_child="/var/run/${name}.pid"
pidfile="/var/run/${name}_daemon.pid"
logfile="/var/log/${name}.log"

load_rc_config ${name}
: ${homeassistant_enable:="NO"}
: ${homeassistant_user:="homeassistant"}
: ${homeassistant_group:="homeassistant"}
: ${homeassistant_config_dir:="/data/home/homeassistant/.homeassistant"}
: ${homeassistant_venv:="/data/home/homeassistant/HA-2026.1"}
: "${homeassistant_restart_delay:=1}"

command="/usr/sbin/daemon"

start_precmd=${name}_prestart
homeassistant_prestart() {
  
  install -g ${homeassistant_group} -m 664 -o ${homeassistant_user} -- /dev/null "${logfile}" \
  && install -g ${homeassistant_group} -m 664 -o ${homeassistant_user} -- /dev/null "${pidfile}" \
  && install -g ${homeassistant_group} -m 664 -o ${homeassistant_user} -- /dev/null "${pidfile_child}" \
  || return 1

  if [ ! -d "${homeassistant_config_dir}" ]; then
    install -d -g ${homeassistant_group} -m 775 -o ${homeassistant_user} -- "${homeassistant_config_dir}" \
    || return 1
  fi
  
  HA_CMD="${homeassistant_venv}/bin/hass"
  HA_ARGS="--ignore-os-check --config ${homeassistant_config_dir}"
  
  if [ -n "${homeassistant_log_file}" ]; then
    install -g ${homeassistant_group} -m 664 -o ${homeassistant_user} -- /dev/null "${homeassistant_log_file}" \
    && HA_ARGS="${HA_ARGS} --log-file ${homeassistant_log_file}"
  fi
  
  if [ -n "${homeassistant_log_rotate_days}" ]; then
    HA_ARGS="${HA_ARGS} --log-rotate-days ${homeassistant_log_rotate_days}"
  fi
  
  rc_flags="-f -o ${logfile} -P ${pidfile} -p ${pidfile_child} -R ${homeassistant_restart_delay} ${HA_CMD} ${HA_ARGS}"
}

start_postcmd=${name}_poststart
homeassistant_poststart() {
  sleep 1
  run_rc_command status
}

restart_precmd="${name}_prerestart"
homeassistant_prerestart() {
  eval "${homeassistant_venv}/bin/hass" --config "${homeassistant_config_dir}" --script check_config
}

status_cmd=${name}_status
homeassistant_status() {
  if [ -n "$rc_pid" ]; then
    echo "${name} is running as pid $rc_pid."
    echo "http://`ifconfig | sed -En \'s/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p\'`:8123"
  else
    echo "${name} is not running."
    return 1
  fi
}

stop_postcmd=${name}_postcmd
homeassistant_postcmd() {
    rm -f -- "${pidfile}"
    rm -f -- "${pidfile_child}"
}

run_rc_command "$1"

EO_RC

	stage_sysrc homeassistant_enable=yes
}

start_homeassistant()
{
	tell_status "starting up homeassistant"
	stage_exec service homeassistant start
}

test_homeassistant()
{
	tell_status "testing homeassistant"
	#stage_test_running
	stage_listening 8123
}

base_snapshot_exists || exit
create_staged_fs homeassistant
start_staged_jail homeassistant
install_homeassistant
configure_homeassistant
start_homeassistant
test_homeassistant
promote_staged_jail homeassistant

# https://www.uoga.net/posts/home-assistant-upgrade-install-in-freebsd-jail/
# https://community.home-assistant.io/t/installation-of-home-assistant-on-your-freenas/195158
