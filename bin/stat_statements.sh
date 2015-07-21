#!/bin/bash

# stat_statements.sh - query statistics monitoring script.
#
# The script connects to STAT_DBNAME, creates its own environment,
# pg_stat_statements and dblink extensions. When STAT_SNAPSHOT is not
# true it prints a top STAT_N queries statistics report for the period
# specified with STAT_SINCE and STAT_TILL. When STAT_ORDER is 0 - it
# prints the top most time consuming queries, 1 - the most often
# called, 2 - the most IO consuming, 3 - the most CPU consuming
# ones. If STAT_SNAPSHOT is true then it creates a snapshot of current
# statements statistics and clean snapshots that are older than and
# period. If STAT_REPLICA_DSN is specified it performs the operation
# on this particular streaming replica. Do not put dbname in the
# STAT_REPLICA_DSN it will be substituted as STAT_DBNAME,
# automatically.
#
# Recommended running frequency - once per 1 hour for reports and once
# per 5 minutes for snapshots.
#
# Compatible with PostgreSQL >=9.2.
#
# Copyright (c) 2013-2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

table_version=2
function_version=7

sql=$(cat <<EOF
DO \$do\$
DECLARE name text;
BEGIN
    IF
        NOT EXISTS (
            SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
    THEN
        CREATE EXTENSION pg_stat_statements;
    END IF;

    IF '$STAT_REPLICA_DSN' <> '' THEN
        IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'dblink') THEN
            CREATE EXTENSION dblink;
        END IF;
    END IF;

    IF
        (
            SELECT pg_catalog.obj_description(c.oid, 'pg_class')
            FROM pg_catalog.pg_class AS c
            JOIN pg_catalog.pg_namespace AS n ON n.oid = relnamespace
            WHERE nspname = 'public' AND relname = 'stat_statements'
        ) IS DISTINCT FROM '$table_version'
    THEN
        DROP TABLE IF EXISTS public.stat_statements;

        CREATE TABLE public.stat_statements AS
        SELECT
            NULL::text AS replica_dsn,
            NULL::timestamp with time zone AS created,
            *
        FROM pg_stat_statements LIMIT 0;

        COMMENT ON TABLE public.stat_statements IS '$table_version';

        CREATE INDEX stat_statements_replica_dns_created_idx
            ON public.stat_statements (replica_dsn, created);
        CREATE INDEX stat_statements_created_idx
            ON public.stat_statements (created);
    END IF;

    IF
        (
            SELECT pg_catalog.obj_description(p.oid, 'pg_proc')
            FROM pg_catalog.pg_proc AS p
            LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = pronamespace
            WHERE nspname = 'public' AND proname = 'stat_statements_get_report'
        ) IS DISTINCT FROM '$function_version' OR TRUE
    THEN
        FOR name IN
            SELECT p.oid::regprocedure
            FROM pg_catalog.pg_proc AS p
            LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = pronamespace
            WHERE nspname = 'public' AND proname = 'stat_statements_get_report'
        LOOP
            EXECUTE 'DROP FUNCTION ' || name;
        END LOOP;

        CREATE OR REPLACE FUNCTION public.stat_statements_get_report(
            i_replica_dsn text,
            i_since timestamp with time zone,
            i_till timestamp with time zone,
            i_n integer,
            i_order integer, -- 0 - time, 1 - calls, 2 - IO time, 3 - CPU time
            OUT o_position integer,
            OUT o_time numeric(18,3),
            OUT o_io_time numeric(18,3),
            OUT o_cpu_time numeric(18,3),
            OUT o_time_percent numeric(5,2),
            OUT o_io_time_percent numeric(5,2),
            OUT o_cpu_time_percent numeric(5,2),
            OUT o_time_avg numeric(18,3),
            OUT o_io_time_avg numeric(18,3),
            OUT o_cpu_time_avg numeric(18,3),
            OUT o_calls integer,
            OUT o_calls_percent numeric(5,2),
            OUT o_rows bigint,
            OUT o_rows_avg numeric(18,3),
            OUT o_users text,
            OUT o_dbs text,
            OUT o_query text
        )
        RETURNS SETOF record LANGUAGE 'plpgsql' AS \$function\$
        BEGIN
            RETURN QUERY (
            WITH du AS (
                SELECT
                    array_agg(
                        DISTINCT usename::text ORDER BY usename::text) AS users,
                    array_agg(
                        DISTINCT datname::text ORDER BY datname::text) AS dbs,
                    regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                        query,
                        E'\\\\?(::[a-zA-Z_]+)?(\\s*,\\s*\\\\?(::[a-zA-Z_]+)?)+', '?', 'gs'),
                        E'\\\\$[0-9]+(::[a-zA-Z_]+)?(\\s*,\\s*\\\\$[0-9]+(::[a-zA-Z_]+)?)*', '$N', 'gs'),
                        E'--.*?$', '', 'gm'),
                        E'\\\\/\\\\*.*?\\\\*\\\\/', '', 'gs')
                        AS normalized_query
                FROM public.stat_statements
                LEFT JOIN pg_catalog.pg_user ON userid = usesysid
                LEFT JOIN pg_catalog.pg_database ON dbid = pg_database.oid
                WHERE
                    replica_dsn = i_replica_dsn AND
                    created BETWEEN coalesce((
                        SELECT created FROM public.stat_statements
                        WHERE replica_dsn = i_replica_dsn AND created < i_since
                        ORDER BY created DESC LIMIT 1
                    ), 'epoch'::date) AND (
                        SELECT created FROM public.stat_statements
                        WHERE replica_dsn = i_replica_dsn AND created < i_till
                        ORDER BY created DESC LIMIT 1
                    )
                GROUP BY normalized_query
            ), s AS (
                SELECT
                    sum(total_time) AS time,
                    sum(blk_read_time) AS blk_read_time,
                    sum(blk_write_time) AS blk_write_time,
                    sum(calls) AS calls,
                    sum(rows) AS rows,
                    regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                        query,
                        E'\\\\?(::[a-zA-Z_]+)?(\\s*,\\s*\\\\?(::[a-zA-Z_]+)?)+', '?', 'gs'),
                        E'\\\\$[0-9]+(::[a-zA-Z_]+)?(\\s*,\\s*\\\\$[0-9]+(::[a-zA-Z_]+)?)*', '$N', 'gs'),
                        E'--.*?$', '', 'gm'),
                        E'\\\\/\\\\*.*?\\\\*\\\\/', '', 'gs')
                        AS normalized_query
                FROM public.stat_statements
                WHERE
                    replica_dsn = i_replica_dsn AND
                    created = (
                        SELECT created FROM public.stat_statements
                        WHERE replica_dsn = i_replica_dsn AND created < i_since
                        ORDER BY created DESC LIMIT 1)
                GROUP BY normalized_query
            ), t AS (
                SELECT
                    sum(total_time) AS time,
                    sum(blk_read_time) AS blk_read_time,
                    sum(blk_write_time) AS blk_write_time,
                    sum(calls) AS calls,
                    sum(rows) AS rows,
                    (array_agg(
                        query ORDER BY length(query)))[1] AS example_query,
                    regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                        query,
                        E'\\\\?(::[a-zA-Z_]+)?(\\s*,\\s*\\\\?(::[a-zA-Z_]+)?)+', '?', 'gs'),
                        E'\\\\$[0-9]+(::[a-zA-Z_]+)?(\\s*,\\s*\\\\$[0-9]+(::[a-zA-Z_]+)?)*', '$N', 'gs'),
                        E'--.*?$', '', 'gm'),
                        E'\\\\/\\\\*.*?\\\\*\\\\/', '', 'gs')
                        AS normalized_query
                FROM public.stat_statements
                WHERE
                    replica_dsn = i_replica_dsn AND
                    created = (
                        SELECT created FROM public.stat_statements
                        WHERE replica_dsn = i_replica_dsn AND created < i_till
                        ORDER BY created DESC LIMIT 1)
                GROUP BY normalized_query
            ), q1 AS (
                SELECT
                    t.time - coalesce(s.time, 0) AS time,
                    t.blk_read_time -
                        coalesce(s.blk_read_time, 0) AS blk_read_time,
                    t.blk_write_time -
                        coalesce(s.blk_write_time, 0) AS blk_write_time,
                    t.rows - coalesce(s.rows, 0) AS rows,
                    t.calls - coalesce(s.calls, 0) AS calls,
                    t.normalized_query,
                    t.example_query
                FROM t LEFT JOIN s USING (normalized_query)
            ), q2 AS (
                SELECT
                    time, rows, calls,
                    blk_read_time + blk_write_time AS io_time,
                    time - (blk_read_time + blk_write_time) AS cpu_time,
                    time::numeric / calls AS time_avg,
                    (blk_read_time + blk_write_time)::numeric /
                        calls AS io_time_avg,
                    (time - (blk_read_time + blk_write_time))::numeric /
                        calls AS cpu_time_avg,
                    rows::numeric / calls AS rows_avg,
                    calls::numeric / sum(calls) OVER v AS calls_percent,
                    CASE
                        WHEN sum(time) OVER v > 0
                        THEN 100.0 * time / sum(time) OVER v
                        ELSE 0
                    END AS time_percent,
                    CASE
                        WHEN sum(blk_read_time + blk_write_time) OVER v > 0
                        THEN
                            100.0 * (blk_read_time + blk_write_time) /
                                sum(blk_read_time + blk_write_time) OVER v
                        ELSE 0
                    END AS io_time_percent,
                    CASE
                        WHEN
                            sum(
                                time -
                                (blk_read_time + blk_write_time)) OVER v > 0
                        THEN
                            100.0 * (time - (blk_read_time + blk_write_time)) /
                                sum(
                                    time -
                                    (blk_read_time + blk_write_time)) OVER v
                        ELSE 0
                    END AS cpu_time_percent,
                    CASE
                        WHEN row_number() OVER w > i_n
                        THEN 'all the other'
                        ELSE array_to_string(users, ', ')
                    END AS users,
                    CASE
                        WHEN row_number() OVER w > i_n
                        THEN 'all the other'
                        ELSE array_to_string(dbs, ', ')
                    END AS dbs,
                    CASE
                        WHEN row_number() OVER w > i_n
                        THEN 'all the other'
                        ELSE example_query
                    END AS example_query
                FROM q1 LEFT JOIN du USING (normalized_query)
                WHERE calls > 0
                WINDOW w AS (
                    ORDER BY
                        CASE
                            WHEN i_order = 0 THEN time
                            WHEN i_order = 1 THEN calls
                            WHEN i_order = 2 THEN blk_read_time + blk_write_time
                            ELSE time - (blk_read_time + blk_write_time)
                        END DESC
                ), v AS ()
            ), q3 AS (
                SELECT
                    sum(time)::numeric(18,3) AS time,
                    sum(io_time)::numeric(18,3) AS io_time,
                    sum(cpu_time)::numeric(18,3) AS cpu_time,
                    sum(time_percent)::numeric(5,2) AS time_percent,
                    sum(io_time_percent)::numeric(5,2) AS io_time_percent,
                    sum(cpu_time_percent)::numeric(5,2) AS cpu_time_percent,
                    avg(time_avg)::numeric(18,3) AS time_avg,
                    avg(io_time_avg)::numeric(18,3) AS io_time_avg,
                    avg(cpu_time_avg)::numeric(18,3) AS cpu_time_avg,
                    sum(calls)::integer AS calls,
                    sum(calls_percent)::numeric(5,2) AS calls_percent,
                    sum(rows)::bigint AS rows,
                    avg(rows_avg)::numeric(18,3) AS rows_avg,
                    users, dbs, example_query
                FROM q2
                GROUP BY users, dbs, example_query
                ORDER BY
                    CASE
                        WHEN i_order = 0 THEN sum(time)
                        WHEN i_order = 1 THEN sum(calls)
                        WHEN i_order = 2 THEN sum(io_time)
                        ELSE sum(cpu_time)
                    END DESC
            )
            SELECT (row_number() OVER ())::integer AS position, *
            FROM q3);
        END \$function\$;

        FOR name IN
            SELECT p.oid::regprocedure
            FROM pg_catalog.pg_proc AS p
            LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = pronamespace
            WHERE nspname = 'public' AND proname = 'stat_statements_get_report'
        LOOP
            EXECUTE 'COMMENT ON FUNCTION ' || name ||
                    ' IS ''$function_version''';
        END LOOP;
    END IF;
END \$do\$;
EOF
)

error=$($PSQL -XAt -c "$sql" $STAT_DBNAME 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not create environment'
        ['2m/detail']=$error))"

if $STAT_SNAPSHOT; then
    delete_sql=$(cat <<EOF
DELETE FROM public.stat_statements
WHERE created < now() - '$STAT_KEEP_SNAPSHOTS'::interval;
EOF
    )

    if [[ -z "$STAT_REPLICA_DSN" ]]; then
        sql=$(cat <<EOF
$delete_sql
INSERT INTO public.stat_statements
SELECT '', now(), * FROM pg_stat_statements;
EOF
        )
    else
        sql=$(cat <<EOF
$delete_sql
INSERT INTO public.stat_statements
SELECT '$STAT_REPLICA_DSN', now(), * FROM dblink(
    '$STAT_REPLICA_DSN dbname=$STAT_DBNAME',
    'SELECT * FROM pg_stat_statements'
) AS s(
    userid oid,
    dbid oid,
    query text,
    calls bigint,
    total_time double precision,
    rows bigint,
    shared_blks_hit bigint,
    shared_blks_read bigint,
    shared_blks_dirtied bigint,
    shared_blks_written bigint,
    local_blks_hit bigint,
    local_blks_read bigint,
    local_blks_dirtied bigint,
    local_blks_written bigint,
    temp_blks_read bigint,
    temp_blks_written bigint,
    blk_read_time double precision,
    blk_write_time double precision
);
EOF
        )
    fi

    error=$($PSQL -XAt -c "$sql" $STAT_DBNAME 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make a snapshot'
            ['2m/detail']=$error))"

    info "$(declare -pA a=(
        ['1/message']='Snapshot has been made'))"
else
    [[ $STAT_ORDER -eq 0 ]] && order='time'
    [[ $STAT_ORDER -eq 1 ]] && order='calls'
    [[ $STAT_ORDER -eq 2 ]] && order='IO time'
    [[ $STAT_ORDER -eq 3 ]] && order='CPU time'

    if [[ -z "$STAT_REPLICA_DSN" ]]; then
        message="Origin report ordered by $order"
    else
        message="Replica report for '$STAT_REPLICA_DSN' ordered by $order"
    fi

    sql=$(cat <<EOF
SELECT * FROM public.stat_statements_get_report(
    '$STAT_REPLICA_DSN', '$STAT_SINCE', '$STAT_TILL', $STAT_N, $STAT_ORDER)
EOF
    )

    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $STAT_DBNAME 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a report'
            ['2m/detail']=$src))"

    while IFS=$'\t' read -r -a l; do
        info "$(declare -pA a=(
            ['1/message']=$message
            ['2/position']=${l[0]}
            ['3/time']=${l[1]}
            ['4/io_time']=${l[2]}
            ['5/cpu_time']=${l[3]}
            ['6/time_percent']=${l[4]}
            ['7/io_time_percent']=${l[5]}
            ['8/cpu_time_percent']=${l[6]}
            ['9/time_avg']=${l[7]}
            ['10/io_time_avg']=${l[8]}
            ['11/cpu_time_avg']=${l[9]}
            ['12/calls']=${l[10]}
            ['13/calls_percent']=${l[11]}
            ['14/rows']=${l[12]}
            ['15/rows_avg']=${l[13]}
            ['16/users']=${l[14]}
            ['17/dbs']=${l[15]}
            ['18m/example_query']=$(printf '%b' "${l[16]}")))"
    done <<< "$src"
fi
