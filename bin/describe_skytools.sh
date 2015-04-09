#!/bin/bash

# describe_skytools.sh - provides details about a Skytools setup.
#
# Collects and prints out:
#
# - per database PgQ version
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# per database  PgQ version

version_sql=$(cat <<EOF
SELECT pgq.version()
EOF
)

(
    db_list=$(
        $PSQL -XAt -c \
            "SELECT datname FROM pg_database WHERE datallowconn" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$db_list))"

    (
        for db in $db_list; do
            schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not check the pgq schema'
                    ['2/database']=$db
                    ['3m/detail']=$schema_line))"

            [ -z "$schema_line" ] && continue

            (
                result=$($PSQL -XAt -c "$version_sql" $db 2>&1) ||
                    die "$(declare -pA a=(
                        ['1/message']='Can not get a version data'
                        ['2/database']=$db
                        ['3m/detail']=$result))"

                info "$(declare -pA a=(
                    ['1/message']='PgQ version'
                    ['2/database']=$db
                    ['3/version']=${result:-null}))"
            )
        done
    )
)
