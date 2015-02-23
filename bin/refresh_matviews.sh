#!/bin/bash

# refresh_matviews.sh - refreshes MVs the smart way.
#
# For the given MATVIEWS_DBNAME the script discovers all the
# materialized views and their indexes, drops the indexes
# concurrently, refreshes the materialized views in their dependencies
# depth order, and creates their indexes concurrently. The script is
# primarily designed to run as a cronjob at periods of
# inactivity. Compatible with PostgreSQL >=9.3.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

sql=$(cat <<EOF
WITH RECURSIVE dependent (c_oid, cr_oids) AS (
    SELECT c.oid, array[0]::oid[]
    FROM pg_class c
    WHERE c.relkind = 'm'
    UNION ALL
    SELECT c.oid, cr.oid || cr_oids
    FROM pg_depend AS d
    JOIN pg_class AS c ON c.oid = d.refobjid
    JOIN pg_rewrite AS r ON r.oid = d.objid
    JOIN pg_class AS cr ON cr.oid = r.ev_class
    JOIN dependent AS dp on dp.c_oid = cr.oid
    WHERE
        c.relkind = 'm' AND cr.relkind = 'm' AND
        d.deptype = 'n' AND d.classid = 'pg_rewrite'::regclass AND
        c.oid <> cr.oid
), matview AS (
    SELECT nspname, relname, depth FROM (
        SELECT
            row_number() OVER w AS r, n.nspname, c.relname,
            array_length(dp.cr_oids, 1) AS depth
        FROM dependent AS dp
        JOIN pg_class AS c ON c.oid = dp.c_oid
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WINDOW w AS (
            PARTITION BY c.oid ORDER BY array_length(dp.cr_oids, 1) DESC)
    ) AS s
    WHERE r = 1
)
(
    SELECT
        regexp_replace(
            indexdef, '^.* INDEX (\\w+).*', 'DROP INDEX CONCURRENTLY \\1;')
    FROM matview AS m
    JOIN pg_catalog.pg_indexes AS i ON
        i.tablename = m.relname AND i.schemaname = m.nspname
    ORDER BY depth DESC
) UNION ALL (
    SELECT
        'REFRESH MATERIALIZED VIEW ' || quote_ident(m.nspname) || '.' ||
        quote_ident(m.relname) || ';'
    FROM matview AS m
    ORDER BY depth DESC
) UNION ALL (
    SELECT
        regexp_replace(
            indexdef, 'INDEX (.+)', 'INDEX CONCURRENTLY \\1;')
    FROM matview AS m
    JOIN pg_catalog.pg_indexes AS i ON
        i.tablename = m.relname AND i.schemaname = m.nspname
    ORDER BY depth DESC
)
EOF
)

for db in $MATVIEWS_DBNAME_LIST; do
    dml=$($PSQL -XAt -c "$sql" $db 2>&1) || \
        die "Can not get a DML to refresh materialized views: $dml."

    if [ -z "$dml" ]; then
        info "No materialized views to refresh."
    else
        refresh_start_time=$(timer)

        no_errors=true
        output_list=''
        while read cmd; do
            output_list="$output_list\n$cmd"

            was_error=false
            error=$($PSQL -XAt -c "$cmd" $db 2>&1) || was_error=true

            if $was_error; then
                output_list="$output_list\n$error"
                no_errors=false
            fi
        done <<< "$dml"

        if $no_errors; then
            info "Materialized views have been successfully refreshed for $db:"\
                 "$output_list"
        else
            die "Can not refresh materialized views for $db:$output_list"
        fi

        refresh_time=$(( ${refresh_time:-0} + $(timer $refresh_start_time) ))
    fi
done

info "Refresh time, s: value ${refresh_time:-N/A}."
