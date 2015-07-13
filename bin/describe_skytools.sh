#!/bin/bash

# describe_skytools.sh - provides details about a Skytools setup.
#
# Collects and prints out:
#
# - per database PgQ version
#
# Recommended running frequency - once per 1 hour.
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

db_list_sql=$(cat <<EOF
SELECT quote_ident(datname) FROM pg_database WHERE datallowconn ORDER BY 1
EOF
)

(
    src=$($PSQL -Xc "\copy ($db_list_sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$src))"

    (
        while IFS=$'\t' read -r -a l; do
            db="${l[0]}"
            schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not check the pgq schema'
                    ['2/database']=$db
                    ['3m/detail']=$schema_line))"

            if [[ -z "$schema_line" ]]; then
                info "$(declare -pA a=(
                    ['1/message']='No PgQ installed'
                    ['2/database']=$db))"
            else
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
            fi
        done <<< "$src"
    )
)
