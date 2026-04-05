#!/bin/sh

set -eu

SUP="/var/qmail/supervise"

install_qmail_smtp_run()
{
	RUN="$SUP/qmail-smtpd/run"
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
	/usr/local/bin/tcpserver -H -R -c10 \
	-u 89 -g 82 0.0.0.0 25 \
	/usr/local/bin/fixcrio \
	/var/qmail/bin/qmail-smtpd /usr/local/vpopmail/bin/vchkpw /usr/bin/true \
	/var/qmail/bin/splogger qmail
EO_SMTP_RUN

	chmod 755 "$RUN"
}

install_qmail_smtp6_run()
{
	RUN="$SUP/qmail-smtpd-6/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/qmail-smtpd-6/log/main"
	cat <<EO_SMTP_RUN > "$RUN"
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/vpopmail/bin
export PATH

if [ ! -f /var/qmail/control/rcpthosts ]; then
	echo "No /var/qmail/control/rcpthosts!"
	echo "Refusing to start SMTP listener because it'll create an open relay"
	exit 1
fi

exec /usr/local/bin/softlimit -m 51200000 \
	/usr/local/bin/tcpserver -H -R -c10 \
	-u 89 -g 82 $(get_jail_ip6 vpopmail) 25 \
	/usr/local/bin/fixcrio \
	/var/qmail/bin/qmail-smtpd /usr/local/vpopmail/bin/vchkpw /usr/bin/true \
	/var/qmail/bin/splogger qmail
EO_SMTP_RUN

	chmod 755 "$RUN"
}

install_log_run()
{
	RUN="$SUP/$1/log/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	cat <<'EO_LOG_RUN' > "$RUN"
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_LOG_RUN

	chmod 755 "$RUN"
}

install_qmail_send_run()
{
	RUN="$SUP/qmail-send/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/qmail-send/log/main"
	#tee $RUN <<'EO_SEND_RUN'
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
	cat <<'EO_QMAILCTL' > "$QCTL"
#!/bin/sh
# description: the qmail MTA
# From LWQ: http://lifewithqmail.org/qmailctl-script-dt70

PATH=/var/qmail/bin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin
export PATH

QMAILDUID=$(id -u qmaild)
NOFILESGID=$(id -g qmaild)
VPOPMAIL=/usr/local/vpopmail

case "$1" in
  start)
    echo "Starting qmail"
    if svok /service/qmail-send ; then
      svc -u /service/qmail-send /service/qmail-send/log
    else
      echo "qmail-send supervise not running"
    fi
    if svok /service/qmail-smtpd ; then
      svc -u /service/qmail-smtpd /service/qmail-smtpd/log
    else
      echo "qmail-smtpd supervise not running"
    fi
    if [ -d /var/lock/subsys ]; then
      touch /var/lock/subsys/qmail
    fi
    ;;
  stop)
    echo "Stopping qmail..."
    echo "  qmail-smtpd"
    svc -d /service/qmail-smtpd /service/qmail-smtpd/log
    echo "  qmail-send"
    svc -d /service/qmail-send /service/qmail-send/log
    if [ -f /var/lock/subsys/qmail ]; then
      rm /var/lock/subsys/qmail
    fi
    ;;
  stat)
    svstat /service/qmail-send
    svstat /service/qmail-send/log
    svstat /service/qmail-smtpd
    svstat /service/qmail-smtpd/log
    qmail-qstat
    ;;
  doqueue|alrm|flush)
    echo "Flushing timeout table and sending ALRM signal to qmail-send."
    /var/qmail/bin/qmail-tcpok
    svc -a /service/qmail-send
    ;;
  queue)
    qmail-qstat
    qmail-qread
    ;;
  reload|hup)
    echo "Sending HUP signal to qmail-send."
    svc -h /service/qmail-send
    ;;
  pause)
    echo "Pausing qmail-send"
    svc -p /service/qmail-send
    echo "Pausing qmail-smtpd"
    svc -p /service/qmail-smtpd
    ;;
  cont)
    echo "Continuing qmail-send"
    svc -c /service/qmail-send
    echo "Continuing qmail-smtpd"
    svc -c /service/qmail-smtpd
    ;;
  restart)
    echo "Restarting qmail:"
    echo "* Stopping qmail-smtpd."
    svc -d /service/qmail-smtpd /service/qmail-smtpd/log
    echo "* Sending qmail-send SIGTERM and restarting."
    svc -t /service/qmail-send /service/qmail-send/log
    echo "* Restarting qmail-smtpd."
    svc -u /service/qmail-smtpd /service/qmail-smtpd/log
    ;;
  cdb)
    if [ -s "$VPOPMAIL/etc/tcp.smtp" ]
    then
      /usr/local/bin/tcprules $VPOPMAIL/etc/tcp.smtp.cdb $VPOPMAIL/etc/tcp.smtp.tmp < $VPOPMAIL/etc/tcp.smtp
      chmod 644 $VPOPMAIL/etc/tcp.smtp*
      echo "Reloaded $VPOPMAIL/etc/tcp.smtp."
    fi

    if [ -s /etc/tcp.smtp ]
    then
      /usr/local/bin/tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
      chmod 644 /etc/tcp.smtp*
        echo "Reloaded /etc/tcp.smtp."
    fi

    if [ -s /var/qmail/control/morercpthosts ]
    then
      if [ -x /var/qmail/bin/qmail-newmrh ]
      then
        /var/qmail/bin/qmail-newmrh
        echo "Reloaded /var/qmail/control/morercpthosts"
      fi
    fi

    if [ -s /var/qmail/users/assign ]
    then
      if [ -x /var/qmail/bin/qmail-newu ]
      then
        /var/qmail/users/assign
        echo "Reloaded /var/qmail/users/assign."
      fi
    fi
    ;;
  help)
    cat <<HELP
   stop -- stops mail service (smtp connections refused, nothing goes out)
  start -- starts mail service (smtp connection accepted, mail can go out)
  pause -- temporarily stops mail service (connections accepted, nothing leaves)
   cont -- continues paused mail service
   stat -- displays status of mail service
    cdb -- rebuild the tcpserver cdb file for smtp
restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
doqueue -- schedules queued messages for immediate delivery
 reload -- sends qmail-send HUP, rereading locals and virtualdomains
  queue -- shows status of queue
   alrm -- same as doqueue
  flush -- same as doqueue
    hup -- same as reload
HELP
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}"
    exit 1
    ;;
esac

exit 0
EO_QMAILCTL
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
	tee "$ETC/tcp.smtp" <<EO_VPOPMAIL_ETC
# if the chkuser patch is compiled into qmail,
# CHKUSER_MBXQUOTA rejects messages when the users mailbox quota is filled
127.0.0.1:allow,RELAYCLIENT=""
${JAIL_NET_PREFIX}.9:allow,RELAYCLIENT=""
:allow,CHKUSER_MBXQUOTA="99"
EO_VPOPMAIL_ETC

	/usr/local/bin/qmailctl cdb
	if [ -f "$ETC/tcp.smtp.cdb" ]; then
		if [ -f "$SUP/qmail-smtpd/run" ]; then
			echo "adding tcp.smtp.cdb to qmail-smtpd/run"
			sed -i.bak \
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

	for _srv in qmail-smtpd qmail-smtpd-6 qmail-send vpopmaild qmail-deliverabled clear; do
		if [ ! -L "/service/$_srv" ] && [ -d "/var/qmail/supervise/$_srv" ]; then
			echo "supervising $_srv"
			ln -s "/var/qmail/supervise/$_srv" "/service/$_srv"
		fi
	done
}

install_vpopmaild_run()
{
	RUN="$SUP/vpopmaild/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/vpopmaild/log/main"
	tee "$RUN" <<'EO_VPOPMAILD'
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
exec /usr/local/bin/tcpserver -HRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild 2>&1 | /usr/bin/logger -t vpopmaild
EO_VPOPMAILD
	chmod 755 "$RUN"
}

install_qmail_deliverabled()
{
	RUN="$SUP/deliverabled/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/deliverabled/log/main"
	#tee "$RUN" <<'EO_DELIVERABLED'
	cat <<'EO_DELIVERABLED' > "$RUN"
#!/bin/sh
MAXRAM=150000000
BIN=/usr/local/bin
PATH=/usr/local/vpopmail/bin
export PATH
exec $BIN/softlimit -m $MAXRAM $BIN/qmail-deliverabled -f 2>&1 | /usr/bin/logger -t qmd
EO_DELIVERABLED
	chmod 755 "$RUN"

	if [ ! "$(pkg query %n -F p5-HTTP-Daemon)" ]; then
		echo "Installing HTTP::Daemon"
		pkg install -y p5-HTTP-Daemon
		# make -C /usr/ports/www/p5-HTTP-Daemon reinstall install clean
	fi

	pkg install -y p5-Package-Constants

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

install_qmail_chkuser()
{
	CHKPATCH="http://opensource.interazioni.it/fileadmin/opensource/pub/download/chkuser/chkuser-2.0.9-release.tar.gz"
	PORTDIR="/usr/ports/mail/qmail"
	PORTBUILDDIR="$PORTDIR/work/netqmail-1.06"
	if [ -d '/tmp/portbuild' ]; then
		PORTBUILDDIR="/tmp/portbuild/$PORTDIR/work/netqmail-1.06"
	fi

	cd "$PORTDIR" && make clean && make
	if [ ! -d "$PORTBUILDDIR" ]; then
		echo "Build directory for qmail not found!" >&2
		exit 1
	fi

	cd "$PORTBUILDDIR"
	fetch -o - "$CHKPATCH" | tar -xzOf - | patch -p1
	if stat -t ./*.rej >/dev/null 2>&1; then
		echo "Patch did not apply cleanly, I refuse to proceed!" >&2
		exit 1
	fi

	echo "chkuser patch applied successfully"
	sleep 2

	sed -i '' -e 's/VPOPMAIL_HOME=\/home\/vpopmail/VPOPMAIL_HOME=\/usr\/local\/vpopmail/g' Makefile
	sed -i '' -e 's/home\/vpopmail/usr\/local\/vpopmail/' conf-cc
	make && make setup && cd "$PORTDIR" && make deinstall && make install clean
}

install_clear_run()
{
	RUN="$SUP/clear/run"
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
	chmod 755 "$RUN"
	touch "$SUP/clear/down"
}

mkdir -p /var/service

install_clear_run
install_qmail_send_run
install_log_run qmail-send
install_qmail_smtp_run
install_log_run qmail-smtpd
install_qmail_smtp6_run
install_log_run qmail-smtpd-6
install_qmailctl
install_vpopmaild_run
install_log_run vpopmaild
install_vpopmail_etc
#install_qmail_chkuser
install_qmail_deliverabled
install_log_run deliverabled
install_symlinks

chmod 755 /service/*/run
chmod 755 /service/*/log/run
chown -R qmaill "$SUP"/*/log

if ! grep -qs svscan_enable /etc/rc.conf; then
	sysrc svscan_enable=YES
fi

service svscan restart
