. mail-toaster.sh

IP=$(get_jail_ip mysql)
if [ "$IP" != "172.16.15.4" ]; then
    echo "ERR: mysql IP is not $IP"
    exit 2
fi

IP=$(get_jail_ip haraka)
if [ "$IP" != "172.16.15.9" ]; then
    echo "ERR: haraka IP is not $IP"
    exit 2
fi

exit 0