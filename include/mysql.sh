#!/bin/sh

set_mysql_password()
{
    if [ -d "$ZFS_JAIL_MNT/mysql/var/db/mysql" ]; then
        # mysql is already provisioned
        return
    fi

    if [ -n "$TOASTER_MYSQL_PASS" ]; then
        # the password is already set
        return
    fi

    tell_status "TOASTER_MYSQL_PASS unset in mail-toaster.conf, generating a password"

    TOASTER_MYSQL_PASS=$(openssl rand -base64 15)
    export TOASTER_MYSQL_PASS

    if grep -sq TOASTER_MYSQL_PASS mail-toaster.conf; then
        sed -i .bak -e "/^export TOASTER_MYSQL_PASS=/ s/=.*$/=\"$TOASTER_MYSQL_PASS\"/" mail-toaster.conf
        rm mail-toaster.conf.bak
    else
        echo "export TOASTER_MYSQL_PASS=\"$TOASTER_MYSQL_PASS\"" >> mail-toaster.conf
    fi
}

mysql_query()
{
    if [ -n "$1" ]; then
        echo "db: $1"
        jexec mysql /usr/local/bin/mysql --password="$TOASTER_MYSQL_PASS" "$1" || return 1
    else
        jexec mysql /usr/local/bin/mysql --password="$TOASTER_MYSQL_PASS" || return 1
    fi

    return 0
}

mysql_create_db()
{
    if mysql_db_exists "$1"; then
        tell_status "db '$1' exists in mysql"
        return 0
    fi

    tell_status "creating mysql database $1"
    echo "CREATE DATABASE $1;" | jexec mysql /usr/local/bin/mysql --password="$TOASTER_MYSQL_PASS" || return 1
    return 0
}

mysql_db_exists()
{
    local _query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1';"
    result=$(echo "$_query" | jexec mysql mysql -s -N --password="$TOASTER_MYSQL_PASS")

    if [ -z "$result" ]; then
        echo "$1 db does not exist"
        return 1
    fi

    echo "$1 db exists"
    return 0
}