#!/bin/bash

# stat_skytools.sh - Skytools statistics collecting script.
#
# Collects a variety of Skytools statistics. Compatible with Skytools
# versions >=3.0.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# pgqd is running

(
    info "$(declare -pA a=(
        ['1/message']='PgQ daemon is running'
        ['2/value']=$(
            ps --no-headers -C pgqd 1>/dev/null 2>&1 &&
                echo 'true' || echo 'false')))"
)

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

# per database top queues by ticker lag
# per database top consumers by lag
# per database top consumers by last seen age

queue_lag_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_SKYTOOLS_TOP_N
         THEN q ELSE 'all the other' END,
    round(avg(v))
FROM (
    SELECT
        queue_name AS q,
        extract(epoch from ticker_lag) AS v,
        row_number() OVER (ORDER BY extract(epoch from ticker_lag) DESC) AS rn
    FROM pgq.get_queue_info()
) AS s
GROUP BY 1
ORDER BY 2 DESC
EOF
)

consumer_lag_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_SKYTOOLS_TOP_N
         THEN q ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_SKYTOOLS_TOP_N
         THEN c ELSE 'all the other' END,
    round(avg(v)) AS v
FROM (
    SELECT
        queue_name AS q, consumer_name AS c,
        extract(epoch from lag) AS v,
        row_number() OVER (ORDER BY extract(epoch from lag) DESC) AS rn
    FROM pgq.get_consumer_info()
) AS s
GROUP BY 1, 2
ORDER BY 3 DESC
EOF
)

consumer_last_seen_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_SKYTOOLS_TOP_N
         THEN q ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_SKYTOOLS_TOP_N
         THEN c ELSE 'all the other' END,
    round(avg(v)) AS v
FROM (
    SELECT
        queue_name AS q, consumer_name AS c,
        extract(epoch from last_seen) AS v,
        row_number() OVER (ORDER BY extract(epoch from last_seen) DESC) AS rn
    FROM pgq.get_consumer_info()
) AS s
GROUP BY 1, 2
ORDER BY 3 DESC
EOF
)

while IFS=$'\t' read -r -a l; do
    db="${l[0]}"
    (
        schema_line=$(
            $PSQL -XAt -c '\dn pgq' $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not check pgq schema for per database charts'
                ['2/db']=$db
                ['3m/detail']=$schema_line))"

        if [[ -z "$schema_line" ]]; then
            note "$(declare -pA a=(
                ['1/message']='Can not stat PgQ for per database charts, it is not instaled'
                ['2/db']=$db))"
        else
            (
                src=$($PSQL -Xc "\copy ($queue_lag_sql) to stdout (NULL 'null')" $db 2>&1) ||
                    die "$(declare -pA a=(
                        ['1/message']='Can not get a queue ticker lag data'
                        ['2/db']=$db
                        ['3m/detail']=$src))"

                if [[ -z "$src" ]]; then
                    info "$(declare -pA a=(
                        ['1/message']='No queues'
                        ['2/db']=$db))"
                else
                    while IFS=$'\t' read -r -a l; do
                        info "$(declare -pA a=(
                            ['1/message']='Top queues by ticker lag, s'
                            ['2/db']=$db
                            ['3/queue_name']=${l[0]}
                            ['4/ticker_lag']=${l[1]}))"
                    done <<< "$src"
                fi
            )

            (
                src=$($PSQL -Xc "\copy ($consumer_lag_sql) to stdout (NULL 'null')" $db 2>&1) ||
                    die "$(declare -pA a=(
                        ['1/message']='Can not get a consumer lag data'
                        ['2/db']=$db
                        ['3m/detail']=$src))"

                if [[ -z "$src" ]]; then
                    info "$(declare -pA a=(
                        ['1/message']='No consumers by lag'
                        ['2/db']=$db))"
                else
                    while IFS=$'\t' read -r -a l; do
                        info "$(declare -pA a=(
                            ['1/message']='Top consumers by lag, s'
                            ['2/db']=$db
                            ['3/queue_name']=${l[0]}
                            ['4/consumer_name']=${l[1]}
                            ['5/lag']=${l[2]}))"
                    done <<< "$src"
                fi
            )

            (
                src=$($PSQL -Xc "\copy ($consumer_last_seen_sql) to stdout (NULL 'null')" $db 2>&1) ||
                    die "$(declare -pA a=(
                        ['1/message']='Can not get a consumer last seen data'
                        ['2/db']=$db
                        ['3m/detail']=$src))"

                if [[ -z "$src" ]]; then
                    info "$(declare -pA a=(
                        ['1/message']='No consumers by last seen'
                        ['2/db']=$db))"
                else
                    while IFS=$'\t' read -r -a l; do
                        info "$(declare -pA a=(
                            ['1/message']='Top consumers by last seen, s'
                            ['2/db']=$db
                            ['3/queue_name']=${l[0]}
                            ['4/consumer_name']=${l[1]}
                            ['5/last_seen']=${l[2]}))"
                    done <<< "$src"
                fi
            )
       fi
    )
done <<< "$db_list_src"

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

        if [[ -z "$schema_line" ]]; then
            note "$(declare -pA a=(
                ['1/message']='Can not stat PgQ for queue aggregates, it is not instaled'
                ['2/db']=$db))"
        else
            src=$($PSQL -Xc "\copy ($queue_aggs_sql) to stdout (NULL 'null')" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a queue aggregates data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            IFS=$'\t' read -r -a l <<< "$src"

            max_ticker_lag=$(
                echo "if ($max_ticker_lag < ${l[0]}) " \
                    "${l[0]} else $max_ticker_lag" \
                    | bc)

            max_fraction=$(
                echo "if ($max_fraction < ${l[1]})" \
                    "${l[1]} else $max_fraction" \
                    | bc | awk '{printf "%.2f", $0}')

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

        if [[ -z "$schema_line" ]]; then
            note "$(declare -pA a=(
                ['1/message']='Can not stat PgQ for consumer aggregates, it is not instaled'
                ['2/db']=$db))"
        else
            src=$($PSQL -Xc "\copy ($consumer_aggs_sql) to stdout (NULL 'null')" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a consumer aggregates data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            IFS=$'\t' read -r -a l <<< "$src"

            max_lag=$(
                echo "if ($max_lag < ${l[0]}) ${l[0]} else $max_lag" | bc)

            max_last_seen=$(
                echo "if ($max_last_seen < ${l[1]})" \
                    "${l[1]} else $max_last_seen" \
                    | bc)

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

        if [[ -z "$schema_line" ]]; then
            note "$(declare -pA a=(
                ['1/message']='Can not stat PgQ for objects, it is not instaled'
                ['2/db']=$db))"
        else
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
