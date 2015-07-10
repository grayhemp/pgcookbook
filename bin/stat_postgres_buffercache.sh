#!/bin/bash

# stat_postgres_buffercache.sh - pg_buffercache stats collection.
#
# Collects and prints out:
#
# - shared buffers distribution
# - top databases by shared buffers utilization
# - top tables by shared buffers utilization
# - top indexes by shared buffers utilization
#
# Recommended running frequency - once per 30 minutes.
#
# Compatible with PostgreSQL >=9.2.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# shared buffers distribution
# top databases by shared buffers utilization

shared_buffers_distribution_sql=$(cat <<EOF
WITH s AS (
    SELECT c.name, coalesce(count, 0) FROM (
        SELECT
            CASE WHEN usagecount IS NULL
                 THEN 'not used' ELSE usagecount::text END ||
            CASE WHEN isdirty THEN ' dirty' ELSE '' END AS name,
            count(1)
        FROM pg_buffercache
        GROUP BY usagecount, isdirty
    ) AS s
    RIGHT JOIN unnest(array[
        '1', '1_dirty', '2', '2_dirty', '3', '3_dirty', '4', '4_dirty',
        '5', '5_dirty', 'not_used'
    ]) AS c(name) USING (name)
    ORDER BY name
)
SELECT row_number() OVER () + 1, * FROM s
EOF
)

databases_by_shared_buffers_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_POSTGRES_BUFFERCACHE_TOP_DATABASES_N
         THEN datname ELSE 'all the other' END,
    sum(cnt)
FROM (
    SELECT
        datname, count(*) AS cnt,
        row_number() OVER (ORDER BY count(*) DESC) AS rn
    FROM pg_buffercache AS b
    JOIN pg_database AS d ON b.reldatabase = d.oid
    WHERE d.datallowconn
    GROUP BY 1
) AS s
GROUP BY 1
ORDER BY 2 DESC
EOF
)

(
    pg_buffercache_line=$(
        $PSQL -XAt -c '\dx pg_buffercache' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not check pg_buffercache extension'
            ['2m/detail']=$pg_buffercache_line))"

    if [[ -z "$pg_buffercache_line" ]]; then
        note "$(declare -pA a=(
            ['1/message']='Can not stat shared buffers, pg_buffercache is not instaled'))"
    else
        (
            src=$($PSQL -Xc "\copy ($shared_buffers_distribution_sql) to stdout (NULL 'null')" 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a buffercache data'
                    ['2m/detail']=$src))"

            declare -A stat=(
                ['1/message']='Shared buffers usage count distribution')

            while IFS=$'\t' read -r -a l; do
                stat["${l[0]}/${l[1]}"]="${l[2]}"
            done <<< "$src"

            info "$(declare -p stat)"
        )

        (
            src=$($PSQL -Xc "\copy ($databases_by_shared_buffers_sql) to stdout (NULL 'null')" 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a buffercache data for databases'
                    ['2m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top databases by shared buffers count'
                    ['2/db']=${l[0]}
                    ['3/value']=${l[1]}))"
            done <<< "$src"
        )
    fi
)

# top tables by shared buffers utilization
# top indexes by shared buffers utilization

db_list_sql=$(cat <<EOF
SELECT datname
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(oid) DESC
EOF
)

tables_by_shared_buffers_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_POSTGRES_BUFFERCACHE_TOP_TABLES_N
         THEN nspname ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_POSTGRES_BUFFERCACHE_TOP_TABLES_N
         THEN relname ELSE 'all the other' END,
    sum(cnt)
FROM (
    SELECT
        n.nspname, c.relname, count(*) AS cnt,
        row_number() OVER (ORDER BY count(*) DESC) AS rn
    FROM pg_buffercache AS b
    JOIN pg_class AS c ON c.relfilenode = b.relfilenode
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 't')
    GROUP BY 1, 2
) AS s
GROUP BY 1, 2
ORDER BY 3 DESC
EOF
)

indexes_by_shared_buffers_sql=$(cat <<EOF
SELECT
    CASE WHEN rn <= $STAT_POSTGRES_BUFFERCACHE_TOP_INDEXES_N
         THEN nspname ELSE 'all the other' END,
    CASE WHEN rn <= $STAT_POSTGRES_BUFFERCACHE_TOP_INDEXES_N
         THEN relname ELSE 'all the other' END,
    sum(cnt)
FROM (
    SELECT
        n.nspname, c.relname, count(*) AS cnt,
        row_number() OVER (ORDER BY count(*) DESC) AS rn
    FROM pg_buffercache AS b
    JOIN pg_class AS c ON c.relfilenode = b.relfilenode
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i'
    GROUP BY 1, 2
) AS s
GROUP BY 1, 2
ORDER BY 3 DESC
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$db_list))"

    for db in $db_list; do
        (
            pg_buffercache_line=$(
                $PSQL -XAt  $db -c '\dx pg_buffercache' 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not check pg_buffercache extension'
                    ['2/db']=$db
                    ['3m/detail']=$pg_buffercache_line))"

            if [[ -z "$pg_buffercache_line" ]]; then
                note "$(declare -pA a=(
                    ['1/message']='Can not stat shared buffers for tables, pg_buffercache is not installed'
                    ['2/db']=$db))"
            else
                (
                    src=$(
                        $PSQL -Xc "\copy ($tables_by_shared_buffers_sql) to stdout (NULL 'null')" \
                            $db 2>&1) ||
                        die "$(declare -pA a=(
                            ['1/message']='Can not get a tables by shared buffers data'
                            ['2/db']=$db
                            ['3m/detail']=$src))"

                    while IFS=$'\t' read -r -a l; do
                        info "$(declare -pA a=(
                            ['1/message']='Top tables by shared buffers count'
                            ['2/db']=$db
                            ['3/schema']=${l[0]}
                            ['4/table']=${l[1]}
                            ['5/value']=${l[2]}))"
                    done <<< "$src"
                )

                (
                    src=$(
                        $PSQL -Xc "\copy ($indexes_by_shared_buffers_sql) to stdout (NULL 'null')" \
                            $db 2>&1) ||
                        die "$(declare -pA a=(
                            ['1/message']='Can not get a buffercache data for indexes'
                            ['2/db']=$db
                            ['3m/detail']=$src))"

                    while IFS=$'\t' read -r -a l; do
                        info "$(declare -pA a=(
                            ['1/message']='Top indexes by shared buffers count'
                            ['2/db']=$db
                            ['3/schema']=${l[0]}
                            ['4/index']=${l[1]}
                            ['5/value']=${l[2]}))"
                    done <<< "$src"
                )
            fi
        )
    done
)
