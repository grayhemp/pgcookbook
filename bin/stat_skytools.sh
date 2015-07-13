#!/bin/bash

# stat_skytools.sh - cluster wide Skytools stats collecting script.
#
# Collects and prints out:
#
# - max queue ticker lag
# - max queue ticker lag fraction of idle period
# - total queue events per second
# - max consumers lag
# - max consumers last seen age
# - total consumer pending events
# - number of queues
# - number of consumers
#
# Recommended running frequency - once per 1 minute.
#
# Compatible with Skytools versions >=3.0.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

db_list_sql=$(cat <<EOF
SELECT quote_ident(datname)
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(oid) DESC
EOF
)

db_list_src=$($PSQL -Xc "\copy ($db_list_sql) to stdout (NULL 'null')" 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not get a database list'
        ['2m/detail']=$db_list))"

# max queue ticker lag
# max queue ticker lag fraction of idle period
# total queue events per second

queue_aggs_sql=$(cat <<EOF
SELECT
    max(extract(epoch from ticker_lag))::integer,
    max(
        extract(epoch from ticker_lag) /
        extract(epoch from queue_ticker_idle_period)),
    sum(ev_per_sec)
FROM pgq.get_queue_info()
EOF
)

(
    max_ticker_lag=0
    max_fraction=0
    total_ev_per_sec=0

    while IFS=$'\t' read -r -a l; do
        db="${l[0]}"

        schema_line=$(
            $PSQL -XAt -c '\dn pgq' $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not check pgq schema for queue aggregates'
                ['2/db']=$db
                ['3m/detail']=$schema_line))"

        if [[ ! -z "$schema_line" ]]; then
            src=$($PSQL -Xc "\copy ($queue_aggs_sql) to stdout (NULL 0)" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a queue aggregates data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            IFS=$'\t' read -r -a l <<< "$src"

            max_ticker_lag=$(
                echo $max_ticker_lag ${l[0]} \
                    | awk '{ print ($1 < $2 ? $2 : $1) }')

            max_fraction=$(
                echo $max_fraction ${l[1]} \
                    | awk '{ printf "%.2f", ($1 < $2 ? $2 : $1) }')

            total_ev_per_sec=$(( $total_ev_per_sec + ${l[2]} ))
        fi
    done <<< "$db_list_src"

    info "$(declare -pA a=(
        ['1/message']='Max queue ticker lag, s'
        ['2/value']=$max_ticker_lag))"

    info "$(declare -pA a=(
        ['1/message']='Max queue ticker lag fraction of idle period'
        ['2/value']=$max_fraction))"

    info "$(declare -pA a=(
        ['1/message']='Total queue events count, /s'
        ['2/value']=$total_ev_per_sec))"
)

# max consumers lag
# max consumers last seen age
# total consumer pending events

consumer_aggs_sql=$(cat <<EOF
SELECT
    max(extract(epoch from lag))::integer,
    max(extract(epoch from last_seen))::integer,
    sum(pending_events)
FROM pgq.get_consumer_info()
EOF
)

(
    max_lag=0
    max_last_seen=0
    total_pending_events=0

    while IFS=$'\t' read -r -a l; do
        db="${l[0]}"

        schema_line=$(
            $PSQL -XAt -c '\dn pgq' $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not check pgq schema for consumer aggregates'
                ['2/db']=$db
                ['3m/detail']=$schema_line))"

        if [[ ! -z "$schema_line" ]]; then
            src=$($PSQL -Xc "\copy ($consumer_aggs_sql) to stdout (NULL 0)" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a consumer aggregates data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            IFS=$'\t' read -r -a l <<< "$src"

            max_lag=$(
                echo $max_lag ${l[0]} \
                    | awk '{ print ($1 < $2 ? $2 : $1) }')

            max_last_seen=$(
                echo $max_last_seen ${l[1]} \
                    | awk '{ print ($1 < $2 ? $2 : $1) }')

            total_pending_events=$(( $total_pending_events + ${l[2]} ))
        fi
    done <<< "$db_list_src"

    info "$(declare -pA a=(
        ['1/message']='Max consumer lag, s'
        ['2/value']=$max_lag))"

    info "$(declare -pA a=(
        ['1/message']='Max consumer last seen age, s'
        ['2/value']=$max_last_seen))"

    info "$(declare -pA a=(
        ['1/message']='Total consumer pending events'
        ['2/value']=$total_pending_events))"
)

# number of queues
# number of consumers

sql=$(cat <<EOF
SELECT
    (SELECT count(1) FROM pgq.get_queue_info()),
    (SELECT count(1) FROM pgq.get_consumer_info())
EOF
)

(
    queue_count=0
    consumer_count=0

    while IFS=$'\t' read -r -a l; do
        db="${l[0]}"

        schema_line=$(
            $PSQL -XAt -c '\dn pgq' $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not check pgq schema for objects'
                ['2/db']=$db
                ['3m/detail']=$schema_line))"

        if [[ ! -z "$schema_line" ]]; then
            src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a queue and consumer counters data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            IFS=$'\t' read -r -a l <<< "$src"

            queue_count=$(( $queue_count + ${l[0]} ))
            consumer_count=$(( $consumer_count + ${l[1]} ))
        fi
    done <<< "$db_list_src"

    info "$(declare -pA a=(
        ['1/message']='Number of objects'
        ['2/queues']=$queue_count
        ['3/consumers']=$consumer_count))"
)
