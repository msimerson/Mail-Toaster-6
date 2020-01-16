#!/bin/sh

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