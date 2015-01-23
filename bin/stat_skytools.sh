#!/bin/bash

# stat_skytools.sh - Skytools statistics collecting script.
#
# Collects a variety of Skytools statistics. Compatible with Skytools#
# versions >=3.0.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# pgqd is running

(
    info "pgqd is running: value "$(
        ps --no-headers -C pgqd 1>/dev/null 2>&1 && echo 't' || echo 'f')'.'
)

# max queue ticker lag
# max queue ticker lag fraction of idle period
# total queue events per second

# max consumers lag
# max consumers last seen age
# total consumer pending events

queue_sql=$(cat <<EOF
SELECT
    max(extract(epoch from ticker_lag))::integer,
    max(
        extract(epoch from ticker_lag) /
        extract(epoch from queue_ticker_idle_period)),
    sum(ev_per_sec)
FROM pgq.get_queue_info()
EOF
)

consumer_sql=$(cat <<EOF
SELECT
    max(extract(epoch from lag))::integer,
    max(extract(epoch from last_seen))::integer,
    sum(pending_events)
FROM pgq.get_consumer_info()
EOF
)

(
    db_list=$(
        $PSQL -XAt -c "SELECT datname FROM pg_database WHERE datallowconn"
        2>&1) ||
        die "Can not get a database list: $src."

    queue_regex='(\S+) (\S+) (\S+)'

    (
        for db in $db_list; do
            schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
                die "Can not check pgq schema: $schema_line."

            [ -z "$schema_line" ] && continue

            src=$($PSQL -XAt -R ' ' -F ' '  -c "$queue_sql" $db 2>&1) ||
                die "Can not get a queue data for $db: $src."

            [ "$src" == '  ' ] && continue

            [[ $src =~ $queue_regex ]] ||
                die "Can not match the queue data: $src."

            ticker_lag=${BASH_REMATCH[1]}
            fraction=${BASH_REMATCH[2]}
            ev_per_sec=${BASH_REMATCH[3]}

            max_ticker_lag=${max_ticker_lag:-0}
            max_ticker_lag=$(
                echo "if ($max_ticker_lag < $ticker_lag)" \
                     "$ticker_lag else $max_ticker_lag" \
                | bc)

            max_fraction=${max_fraction:-0}
            max_fraction=$(
                echo "if ($max_fraction < $fraction)" \
                     "$fraction else $max_fraction" \
                | bc | awk '{printf "%.2f", $0}')

            total_ev_per_sec=$(( ${total_ev_per_sec:-0} + $ev_per_sec))
        done

        info "Max queue ticker lag, s: value ${max_ticker_lag:-N/A}."
        info "Max queue ticker lag fraction of idle period: value" \
             "${max_fraction:-N/A}."
        info "Total queue events count, /s: value ${total_ev_per_sec:-N/A}."
    )

    consumer_regex='(\S+) (\S+) (\S+)'

    (
        for db in $db_list; do
            schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
                die "Can not check pgq schema: $schema_line."

            [ -z "$schema_line" ] && continue

            src=$($PSQL -XAt -R ' ' -F ' '  -c "$consumer_sql" $db 2>&1) ||
                die "Can not get a consumer data for $db: $src."

            [ "$src" == '  ' ] && continue

            [[ $src =~ $consumer_regex ]] ||
                die "Can not match the consumer data: $src."

            lag=${BASH_REMATCH[1]}
            last_seen=${BASH_REMATCH[2]}
            pending_events=${BASH_REMATCH[3]}

            max_lag=${max_lag:-0}
            max_lag=$(echo "if ($max_lag < $lag) $lag else $max_lag" | bc)

            max_last_seen=${max_last_seen:-0}
            max_last_seen=$(
                echo "if ($max_last_seen < $last_seen)" \
                     "$last_seen else $max_last_seen" \
                | bc)

            total_pending_events=$((
                ${total_pending_events:-0} + $pending_events))
        done

        info "Max consumer lag, s: value ${max_lag:-N/A}."
        info "Max consumer last seen age, s: value ${max_last_seen:-N/A}."
        info "Total consumer pending events:" \
             "count ${total_pending_events:-N/A}."
    )
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
    db_list=$(
        $PSQL -XAt -c "SELECT datname FROM pg_database WHERE datallowconn"
        2>&1) ||
        die "Can not get a database list: $src."

    regex='(\S+) (\S+)'

    for db in $db_list; do
        schema_line=$($PSQL -XAtc '\dn pgq' $db 2>&1) ||
            die "Can not check pgq schema: $schema_line."

        [ -z "$schema_line" ] && continue

        src=$($PSQL -XAt -R ' ' -F ' '  -c "$sql" $db 2>&1) ||
            die "Can not get a queue and consumer counters data for $db: $src."

        [[ $src =~ $regex ]] ||
            die "Can not match the queue and consumer counters data: $src."

        queue_count=$(( ${queue_count:0} + ${BASH_REMATCH[1]} ))
        consumer_count=$(( ${consumer_count:0} + ${BASH_REMATCH[2]} ))
    done

    info "Number of objects: queues $queue_count, consumer $consumer_count."
)
