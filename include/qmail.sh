#!/bin/sh

set -eu

SUP="/var/qmail/supervise"

install_service_qmail_smtp()
{
	local RUN="$SUP/qmail-smtpd/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/qmail-smtpd/log/main"
	cat <<'EO_SMTP_RUN' > "$RUN"
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/vpopmail/bin
export PATH

if [ ! -f /var/qmail/control/rcpthosts ]; then
	echo "No /var/qmail/control/rcpthosts!"
	echo "Refusing to start SMTP listener because it'll create an open relay"
	exit 1
fi

exec /usr/local/bin/softlimit -m 51200000 \
	/usr/local/bin/tcpserver -H -R -c10 -6 \
	-u 89 -g 82 ::0 25 \
	/usr/local/bin/fixcrio \
	/var/qmail/bin/qmail-smtpd /usr/local/vpopmail/bin/vchkpw /usr/bin/true \
	/var/qmail/bin/splogger qmail
EO_SMTP_RUN

	chmod 755 "$RUN"
}

# $1 is the service, $2 (optional) a syslog tag: the service's output then goes
# to syslog under that tag, otherwise to multilog in ./main
install_service_log_run()
{
	local RUN="$SUP/$1/log/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	if [ -n "${2:-}" ]; then
		cat <<EO_LOG_RUN_SYSLOG > "$RUN"
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/bin/logger -t $2
EO_LOG_RUN_SYSLOG
	else
		cat <<'EO_LOG_RUN' > "$RUN"
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_LOG_RUN
	fi

	chmod 755 "$RUN"
}

# A daemon that outlived its supervise is the child of init and holds the port,
# and a new instance can then never bind (the run script piped into logger, so
# svc -t killed the shell and not the daemon). Print the pids of the processes
# whose command line matches the awk regex $1 and whose parent is init.
qmail_orphans()
{
	ps -ax -o pid=,ppid=,command= | awk -v re="$1" \
		'$2 == 1 && $0 ~ re && $0 !~ /awk/ { print $1 }'
}

# The daemon answers with what it loaded at start, until it is killed by hand.
kill_orphaned_daemon()
{
	local _pid
	for _pid in $(qmail_orphans "$1"); do
		echo "killing orphaned $1 (pid $_pid), it holds the port"
		kill "$_pid" || true
	done
}

install_service_qmail_send()
{
	local RUN="$SUP/qmail-send/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/qmail-send/log/main"
	cat <<'EO_SEND_RUN' > "$RUN"
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
exec /var/qmail/bin/qmail-start ./Maildir/ \
	/var/qmail/bin/splogger qmail
EO_SEND_RUN

	chmod 755 "$RUN"
}

install_qmailctl()
{
	if [ ! -d "/var/qmail/bin" ]; then
		mkdir -p /var/qmail/bin
	fi

	QCTL="/var/qmail/bin/qmailctl"
	if [ -x "$QCTL" ]; then
		echo -n "Re"
	fi

	echo "installing $QCTL"
	fetch -o "$QCTL" "$TOASTER_SRC_URL/qmail/qmailctl.sh"
	chmod 755 "$QCTL"
	QCTLBIN="/usr/local/bin/qmailctl"
	if [ ! -L "$QCTLBIN" ];
	then
		ln -s "$QCTL" "$QCTLBIN"
	fi
}

install_vpopmail_etc()
{
	ETC="/usr/local/vpopmail/etc"
	if [ -s "$ETC/tcp.smtp" ]; then
		echo -n "Re"
	fi

	echo "installing $ETC/tcp.smtp"
	mkdir -p "$ETC" || exit
	cat <<EO_VPOPMAIL_ETC > "$ETC/tcp.smtp"
127.0.0.1:allow,RELAYCLIENT=""
${JAIL_NET_PREFIX}.9:allow,RELAYCLIENT=""
:allow
EO_VPOPMAIL_ETC

	/usr/local/bin/qmailctl cdb

	if [ -f "$ETC/tcp.smtp.cdb" ]; then
		if [ -f "$SUP/qmail-smtpd/run" ]; then
			echo "adding tcp.smtp.cdb to qmail-smtpd/run"
			sed -i '' \
				-e '/-u 89/ s/-g 82/-g 82 -x \/usr\/local\/vpopmail\/etc\/tcp.smtp.cdb/' \
				"$SUP/qmail-smtpd/run"
		fi
	fi
}

install_symlinks()
{
	if [ ! -L "/service" ]; then
		echo "ln -s /var/service /service"
		ln -s /var/service /service
	fi

	for _srv in qmail-smtpd qmail-send vpopmaild deliverabled clear; do
		if [ ! -L "/service/$_srv" ] && [ -d "$SUP/$_srv" ]; then
			echo "supervising $_srv"
			ln -s "$SUP/$_srv" "/service/$_srv"
		fi
	done
}

install_service_vpopmaild()
{
	local RUN="$SUP/vpopmaild/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/vpopmaild/log/main"
	cat <<'EO_VPOPMAILD' > "$RUN"
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
# no pipe: exec has to replace the shell, or svc -t signals the shell and
# leaves tcpserver running. Output goes to the log service (log/run).
exec /usr/local/bin/tcpserver -HRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild 2>&1
EO_VPOPMAILD
}

install_qmail_deliverabled()
{
	if [ ! "$(pkg query %n -F p5-HTTP-Daemon)" ]; then
		echo "Installing HTTP::Daemon"
		pkg install -y p5-HTTP-Daemon
	fi

	echo "installing Qmail::Deliverable"
	pkg install -y p5-Log-Message p5-Archive-Extract p5-Object-Accessor p5-Module-Pluggable p5-libwww
	export PERL_MM_USE_DEFAULT=1
	yes | cpan -fi install Qmail::Deliverable

	if [ "$TOASTER_VPOPMAIL_EXT" = "1" ]; then
		sed -i '' -e '/Getopt::Long::Configure("bundling");/a\
$Qmail::Deliverable::VPOPMAIL_EXT = 1;
' /usr/local/bin/qmail-deliverabled
	fi
}

install_service_qmail_deliverabled()
{
	local RUN="$SUP/deliverabled/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/deliverabled/log/main"
	cat <<'EO_DELIVERABLED' > "$RUN"
#!/bin/sh
MAXRAM=150000000
BIN=/usr/local/bin
PATH=/usr/local/vpopmail/bin
export PATH
# no pipe: exec has to replace the shell, or svc -t signals the shell and
# leaves qmail-deliverabled running. Output goes to the log service (log/run).
exec $BIN/softlimit -m $MAXRAM $BIN/qmail-deliverabled -f 2>&1
EO_DELIVERABLED
}

install_service_clear()
{
	local RUN="$SUP/clear/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/clear"
	cat <<'EO_CLEAR' > "$RUN"
	#!/bin/sh
yes '' | head -4000 | tr '\n' .

# To clear service errors, run this command:
# svc -o /service/clear
EO_CLEAR
	touch "$SUP/clear/down"
}

install_supervision()
{
	mkdir -p /var/service

	install_qmailctl
	install_qmail_deliverabled

	install_service_clear
	install_service_qmail_send
	install_service_qmail_smtp
	install_service_qmail_deliverabled
	install_service_vpopmaild
	chmod 755 "$SUP"/*/run

	install_service_log_run qmail-send
	install_service_log_run qmail-smtpd
	install_service_log_run deliverabled qmd
	install_service_log_run vpopmaild vpopmaild
	chmod 755 "$SUP"/*/log/run
	chown -R qmaill "$SUP"/*/log

	# a rerun on a live jail: instances left by the old run scripts
	kill_orphaned_daemon 'qmail-deliverabled'
	kill_orphaned_daemon 'tcpserver.*vpopmaild'

	install_vpopmail_etc
	install_symlinks
}
