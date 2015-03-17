#!/bin/bash

# describe_skytools.sh - Skytools description script.
#
# Collects info about Skytools. Compatible with versions >=3.0.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# per database version
# per database top queues by ticker lag
# per database top consumers by lag
# per database top consumers by last seen age

version_sql=$(cat <<EOF
SELECT pgq.version()
EOF
)

queue_lag_sql=$(cat <<EOF
SELECT queue_name, extract(epoch from ticker_lag)::integer
FROM pgq.get_queue_info()
ORDER BY 2 DESC LIMIT 5
EOF
)

consumer_lag_sql=$(cat <<EOF
SELECT queue_name, consumer_name, extract(epoch from lag)::integer
FROM pgq.get_consumer_info()
ORDER BY 3 DESC LIMIT 5
EOF
)

consumer_last_seen_sql=$(cat <<EOF
SELECT queue_name, consumer_name, extract(epoch from last_seen)::integer
FROM pgq.get_consumer_info()
ORDER BY 3 DESC LIMIT 5
EOF
)

(
    db_list=$(
        $PSQL -XAt -c "SELECT datname FROM pg_database WHERE datallowconn"
        2>&1) ||
        die "Can not get a database list: $src."

    (
        for db in $db_list; do
            schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
                die "Can not check pgq schema for $db: $schema_line."

            [ -z "$schema_line" ] && continue

            (
                result=$(
                    $PSQL -XAt -c "$version_sql" $db 2>&1) ||
                    die "Can not get a version data for $db: $result."

                info "PgQ version for $db: ${result:-N/A}."
            )

            (
                result=$(
                    $PSQL -XAt -R ', ' -F ' '  -c "$queue_lag_sql" $db 2>&1) ||
                    die "Can not get a queue lag data for $db: $result."

                info "Top queues by ticker lag for $db, s: ${result:-N/A}."
            )

            (
                result=$(
                    $PSQL -XAt -R ', ' -F ' '  -c "$consumer_lag_sql" $db \
                    2>&1) ||
                    die "Can not get a consumer lag data for $db: $result."

                info "Top consumers by lag for $db, s: ${result:-N/A}."
            )

            (
                result=$(
                    $PSQL -XAt -R ', ' -F ' '  -c "$consumer_last_seen_sql" \
                    $db 2>&1) ||
                    die "Can not get a consumers last seen data for $db:" \
                        "$result."

                info "Top consumers by last seen age for $db, s:" \
                     "${result:-N/A}."
            )
        done
    )
)
