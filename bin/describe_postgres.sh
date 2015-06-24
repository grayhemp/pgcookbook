#!/bin/bash

# describe_postgres.sh - provides details about a PostgreSQL instance.
#
# Collects and prints out:
#
# - version
# - tablespaces
# - custom settings
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# version information

(
    src=$($PSQL -XAtc 'SELECT version()' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a version data'
            ['2m/detail']=$src))"

    regex='^\S+ (.+) on (\S+),'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the version data'
            ['2m/data']=$src))"

    version=${BASH_REMATCH[1]}
    arch=${BASH_REMATCH[2]}

    info "$(declare -pA a=(
        ['1/message']='Version'
        ['2/version']=$version
        ['3/arch']=$arch))"
)

# tablespaces

sql=$(cat <<EOF
SELECT
    spcname,
    pg_catalog.pg_get_userbyid(spcowner),
    nullif(pg_catalog.pg_tablespace_location(oid), '')
FROM pg_catalog.pg_tablespace
ORDER BY 1
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a tablespace data'
            ['2m/detail']=$src))"

    while IFS=$'\t' read -r -a l; do
        (
            name=${l[0]}
            owner=${l[1]}
            location=${l[2]}

            info "$(declare -pA a=(
                ['1/message']='Tablespace'
                ['2/name']=$name
                ['3/owner']=$owner
                ['4/location']=$location))"
        )
    done <<< "$src"
)

# custom settings

sql=$(cat <<EOF
SELECT name, setting
FROM pg_settings
WHERE source NOT IN ('default', 'client');
EOF
)

(
    src=$(
        ($PSQL -XAt -c "$sql" \
            | cut -d '|' -f 1,2 | grep -E "$settings_regex") 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a settings data'
            ['2m/detail']=$src))"

    declare -A a=(
        ['1/message']='Custom settings')

    count=2
    while read l; do
        a["$count/${l%%|*}"]="${l#*|}"
        (( count++ ))
    done <<< "$src"

    info "$(declare -p a)"
)
