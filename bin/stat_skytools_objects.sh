#!/bin/bash

# stat_skytools_objects.sh - Skytools objects stats collecting script.
#
# Collects and prints out:
#
# - per database top queues by ticker lag
# - per database top consumers by lag
# - per database top consumers by last seen age
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

# per database top queues by ticker lag
# per database top consumers by lag
# per database top consumers by last seen age

queue_lag_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_SKYTOOLS_OBJECTS_TOP_N
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
    CASE WHEN rn <= $STAT_SKYTOOLS_OBJECTS_TOP_N
         THEN q ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_SKYTOOLS_OBJECTS_TOP_N
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
    CASE WHEN rn <= $STAT_SKYTOOLS_OBJECTS_TOP_N
         THEN q ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_SKYTOOLS_OBJECTS_TOP_N
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

        if [[ ! -z "$schema_line" ]]; then
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
