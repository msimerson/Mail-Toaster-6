#!/bin/sh

SUP="/var/qmail/supervise"
mkdir -p /var/service

install_qmail_smtp_run()
{
	RUN="$SUP/qmail-smtpd/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

    echo "installing $RUN"
	mkdir -p $SUP/qmail-smtpd/log/main
#tee $RUN <<'EO_SMTP_RUN'
	cat <<'EO_SMTP_RUN' > $RUN
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

	chmod 755 $RUN
}

install_qmail_smtp_log_run()
{
	RUN="$SUP/qmail-smtpd/log/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

	echo "installing $RUN"
	#tee $RUN <<'EO_SMTP_LOG_RUN'
	cat <<'EO_SMTP_LOG_RUN' > $RUN
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_SMTP_LOG_RUN

	chmod 755 $RUN
}

install_qmail_send_run()
{
	RUN="$SUP/qmail-send/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

    echo "installing $RUN"
	mkdir -p $SUP/qmail-send/log/main
	#tee $RUN <<'EO_SEND_RUN'
	cat <<'EO_SEND_RUN' > $RUN
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
exec /var/qmail/bin/qmail-start ./Maildir/ \
	/var/qmail/bin/splogger qmail
EO_SEND_RUN

	chmod 755 $RUN
}

install_qmail_send_log_run()
{
	RUN="$SUP/qmail-send/log/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

	echo "installing $RUN"
	#tee $RUN <<'EO_SEND_LOG_RUN'
	cat <<'EO_SEND_LOG_RUN' > $RUN
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_SEND_LOG_RUN

	chmod 755 $RUN
}

install_qmailctl()
{
	if [ ! -d "/var/qmail/bin" ];
	then
		mkdir -p /var/qmail/bin
	fi

	QCTL="/var/qmail/bin/qmailctl"
	if [ -x "$QCTL" ];
	then
		echo -n "Re"
	fi

	echo "installing $QCTL"
	#tee $QCTL <<'EO_QMAILCTL'
	cat <<'EO_QMAILCTL' >  $QCTL
#!/bin/sh
# description: the qmail MTA
# From LWQ: http://lifewithqmail.org/qmailctl-script-dt70

PATH=/var/qmail/bin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin
export PATH

QMAILDUID=`id -u qmaild`
NOFILESGID=`id -g qmaild`
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
	chmod 755 $QCTL
	QCTLBIN="/usr/local/bin/qmailctl"
	if [ ! -L "$QCTLBIN" ];
	then
		ln -s $QCTL $QCTLBIN
	fi
}

install_vpopmail_etc()
{
	ETC="/usr/local/vpopmail/etc"
	if [ -s "$ETC/tcp.smtp" ]; then
		echo -n "Re"
	fi

	echo "installing $ETC/tcp.smtp"
	mkdir -p $ETC || exit
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
            sed -i .bak \
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

	if [ ! -L "/service/qmail-smtpd" ]; then
		echo "supervising qmail-smtpd"
		ln -s /var/qmail/supervise/qmail-smtpd /service/qmail-smtpd
	fi

	if [ ! -L "/service/qmail-send" ]; then
		echo "supervising qmail-send"
		ln -s /var/qmail/supervise/qmail-send /service/qmail-send
	fi

	if [ ! -L "/service/vpopmaild" ]; then
		echo "supervising vpopmaild"
		ln -s /var/qmail/supervise/vpopmaild /service/vpopmaild
	fi

	if [ ! -L "/service/qmail-deliverabled" ]; then
		echo "supervising qmail-deliverabled"
		ln -s /var/qmail/supervise/deliverabled /service/qmail-deliverabled
	fi

	if [ ! -L "/service/clear" ]; then
		if [ -d "/var/qmail/supervise/clear" ]; then
			ln -s /var/qmail/supervise/clear /service/clear
		fi
	fi
}

install_vpopmaild_run()
{
	RUN="$SUP/vpopmaild/run"
	LOGRUN="$SUP/vpopmaild/log/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/vpopmaild/log/main"
	tee "$RUN" <<'EO_VPOPMAILD'
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
exec /usr/local/bin/tcpserver -vHRD 0.0.0.0 89 /usr/local/vpopmail/bin/vpopmaild 2>&1 | /usr/bin/logger -t vpopmaild
EO_VPOPMAILD
	chmod 755 $RUN

	echo "installing $LOGRUN"
	tee "$LOGRUN" <<'EO_VPOPMAILD_LOG'
#!/bin/sh
PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_VPOPMAILD_LOG
	chmod 755 "$LOGRUN"
}

install_qmail_deliverabled()
{
	RUN="$SUP/deliverabled/run"
	LOGRUN="$SUP/deliverabled/log/run"
	if [ -x "$RUN" ];
	then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/deliverabled/log/main"
	#tee "$RUN" <<'EO_DELIVERABLED'
	cat <<'EO_DELIVERABLED' > $RUN
#!/bin/sh
MAXRAM=150000000
BIN=/usr/local/bin
PATH=/usr/local/vpopmail/bin
export PATH
exec $BIN/softlimit -m $MAXRAM $BIN/qmail-deliverabled -f 2>&1 | /usr/bin/logger -t qmd
EO_DELIVERABLED
	chmod 755 $RUN

	#tee "$LOGRUN" <<'EO_DELIVERABLED_RUN'
	cat <<'EO_DELIVERABLED_RUN' > "$LOGRUN"
#!/bin/sh
exec /usr/local/bin/setuidgid qmaill /usr/local/bin/multilog ./main
EO_DELIVERABLED_RUN
	chmod 755 "$LOGRUN"

	if [ ! "$(pkg query %n -F p5-HTTP-Daemon)" ]; then
		echo "Installing HTTP::Daemon"
		pkg install -y p5-HTTP-Daemon
		make -C /usr/ports/www/p5-HTTP-Daemon deinstall install clean
	fi

	echo "installing Qmail::Deliverable"
    pkg install -y p5-HTTP-Daemon p5-Log-Message p5-Archive-Extract p5-Object-Accessor p5-Module-Pluggable p5-CPANPLUS
	perl -MCPANPLUS -e 'install Qmail::Deliverable'
}

install_qmail_chkuser()
{
	CHKPATCH=http://opensource.interazioni.it/fileadmin/opensource/pub/download/chkuser/chkuser-2.0.9-release.tar.gz
	PORTDIR=/usr/ports/mail/qmail
	PORTBUILDDIR=$PORTDIR/work/netqmail-1.06
	if [ -d '/tmp/portbuild' ]; then
		PORTBUILDDIR=/tmp/portbuild/$PORTDIR/work/netqmail-1.06
	fi

	cd $PORTDIR && make clean && make
	if [ ! -d "$PORTBUILDDIR" ]; then
		echo "Build directory for qmail not found!";
		exit
	fi

	cd $PORTBUILDDIR || exit
	fetch -o - $CHKPATCH | tar -xzOf - | patch -p1
	if stat -t ./*.rej >/dev/null 2>&1; then
		echo "Patch did not apply cleanly, I refuse to proceed!"
		exit
	fi

	echo "chkuser patch applied successfully"
	sleep 2;

	sed -i -e 's/VPOPMAIL_HOME=\/home\/vpopmail/VPOPMAIL_HOME=\/usr\/local\/vpopmail/g' Makefile
	sed -i -e 's/home\/vpopmail/usr\/local\/vpopmail/' conf-cc
	make && make setup && cd $PORTDIR && make deinstall && make install clean
}

install_clear_run()
{
	RUN="$SUP/clear/run"
	if [ -x "$RUN" ]; then
		echo -n "Re"
	fi

	echo "installing $RUN"
	mkdir -p "$SUP/clear"
	cat <<'EO_CLEAR' > $RUN
	#!/bin/sh
yes '' | head -4000 | tr '\n' .

# To clear service errors, run this command:
# svc -o /service/clear
EO_CLEAR
	chmod 755 $RUN
	touch $SUP/clear/down
}

install_clear_run
install_qmail_send_run
install_qmail_send_log_run
install_qmail_smtp_run
install_qmail_smtp_log_run
install_qmailctl
install_vpopmaild_run
install_vpopmail_etc
#install_qmail_chkuser
install_qmail_deliverabled
install_symlinks

chmod 755 /service/*/run
chmod 755 /service/*/log/run
chown -R qmaill $SUP/*/log

if ! grep -qs svscan_enable /etc/rc.conf; then
	sysrc svscan_enable=YES
fi

service svscan restart
