#!/bin/bash

# describe_pgbouncer.sh - prints PgBouncer instance details.
#
# Prints version and configuration. Do not forget to specify an
# appropriate connection parameters for monitored instnces.
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
    src=$($PSQL -XAtc 'SHOW VERSION' pgbouncer 2>&1) || \
        die "Can not get a version data for $instance_dsn: $version."
    src=$(echo "$src" | sed -r 's/\s+/ /g')

    regex='\S+ \S+ \S+ (\S+)'

    [[ $src =~ $regex ]] ||
        die "Can not match the version data: $src."

    version=${BASH_REMATCH[1]}

    info "Version for $instance_dsn: version $version."
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
    result=$($PSQL -XAt -F ' ' -c 'SHOW CONFIG' pgbouncer 2>&1) || \
        die "Can not get a config data for $instance_dsn: $result."
    result=$(
        echo "$result" | cut -d ' ' -f 1,2 | grep -E "$settings_regex" \
        | paste -sd ',' | sed -r 's/,/, /g')

    info "Settings for $instance_dsn: $result."
)
