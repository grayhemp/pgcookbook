#!/bin/bash

# describe_pgbouncer.sh - provides details about a PgBouncer instance.
#
# Collects and prints out:
#
# - version
# - important settings
#
# Recommended running frequency - once per 1 hour.
#
# Do not forget to specify appropriate connection parameters for
# monitored instances.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

instance_dsn=$(
    echo $([ ! -z "$HOST" ] && echo "host=$HOST") \
         $([ ! -z "$PORT" ] && echo "port=$PORT"))

# version

(
    src=$($PSQL -XAtc 'SHOW VERSION' pgbouncer 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a version data'
            ['2/dsn']=$instance_dsn
            ['3m/detail']=$src))"

    regex='\S+\s+\S+ \S+ (\S+)'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the version data'
            ['2m/src']=$src))"

    version=${BASH_REMATCH[1]}

    info "$(declare -pA a=(
        ['1/message']='Version'
        ['2/dsn']=$instance_dsn
        ['3/version']=$version))"
)

# settings

settings_regex=$(cat <<EOF
pool_mode|max_client_conn|default_pool_size|autodb_idle_timeout|query_timeout|\
query_wait_timeout|client_idle_timeout|client_login_timeout|\
idle_transaction_timeout|server_lifetime|server_idle_timeout|\
server_connect_timeout|server_login_retry|ignore_startup_parameters
EOF
)

(
    src=$(
        ($PSQL -XAt -c 'SHOW CONFIG' pgbouncer \
            | cut -d '|' -f 1,2 | grep -E "$settings_regex") 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a settings data'
            ['2/dsn']=$instance_dsn
            ['3m/detail']=$src))"

    declare -A a=(
        ['1/message']='Settings'
        ['2/dsn']=$instance_dsn)

    count=3
    while read l; do
        a["$count/${l%%|*}"]="${l#*|}"
        (( count++ ))
    done <<< "$src"

    info "$(declare -p a)"
)
