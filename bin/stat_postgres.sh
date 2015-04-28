#!/bin/bash

# stat_postgres.sh - PostgreSQL instance statistics collecting script.
#
# Collects a variety of postgres related statistics. Compatible with
# PostgreSQL >=9.2.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_POSTGRES_FILE

# instance responsiveness

(
    info "$(declare -pA a=(
        ['1/message']='Instance responsiveness'
        ['2/value']=$(
            $PSQL -XAtc 'SELECT true::text' 2>/dev/null || echo 'false')))"
)

# postgres processes count

(
    info "$(declare -pA a=(
        ['1/message']='Postgres processes count'
        ['2/value']=$(ps --no-headers -C postgres | wc -l)))"
)

# data size for database, filesystem except xlog, xlog

(
    db_size=$(
        $PSQL -XAtc 'SELECT sum(pg_database_size(oid)) FROM pg_database' \
            2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database size data'
            ['2m/detail']=$db_size))"

    data_dir=$($PSQL -XAtc 'SHOW data_directory' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a data dir'
            ['2m/detail']=$data_dir))"

    fs_size=$((
        du -b --exclude pg_xlog -sL "$data_dir" | sed -r 's/\s+.+//') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a filesystem size data'
            ['2m/detail']=$fs_size))"

    wal_size=$((du -b -sL "$data_dir/pg_xlog" | sed -r 's/\s+.+//') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get an xlog size data'
            ['2m/detail']=$wal_size))"

    info "$(declare -pA a=(
        ['1/message']='Data size, B'
        ['2/db']=$db_size
        ['3/filesystem_except_xlog']=$fs_size
        ['4/xlog']=$wal_size))"
)

# top databases by size

sql=$(cat <<EOF
SELECT datname, pg_database_size(oid)
FROM pg_database
WHERE datallowconn
ORDER BY 2 DESC
LIMIT 5
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database data'
            ['2m/detail']=$src))"

    while IFS=$'\t' read -r -a l; do
        info "$(declare -pA a=(
            ['1/message']='Top databases by size, B'
            ['2/db']=${l[0]}
            ['3/value']=${l[1]}))"
    done <<< "$src"
)

# top databases by shared buffers utilization

sql=$(cat <<EOF
SELECT datname, count(*)
FROM pg_buffercache AS b
JOIN pg_database AS d ON b.reldatabase = d.oid
WHERE d.datallowconn
GROUP BY 1 ORDER BY 2 DESC
LIMIT 5
EOF
)

(
    extension_line=$($PSQL -XAtc '\dx pg_buffercache' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not check pg_buffercache extension'
            ['2m/detail']=$extension_line))"

    if [[ -z "$extension_line" ]]; then
        note "$(declare -pA a=(
            ['1/message']='Can not stat shared buffers for databases, pg_buffercache is not installed'))"
    else
        src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a buffercache data for databases'
                ['2m/detail']=$src))"

        while IFS=$'\t' read -r -a l; do
            info "$(declare -pA a=(
                ['1/message']='Top databases by shared buffers count'
                ['2/db']=${l[0]}
                ['3/value']=${l[1]}))"
        done <<< "$src"
    fi
)

# top tables by total size
# top tables by tuple count
# top tables by shared buffers utilization
# top tables by total fetched tuples
# top tables by total inserted, updated and deleted rows
# top tables by total seq scan row count
# top tables by total least HOT-updated rows, n_tup_upd - n_tup_hot_upd
# top tables by dead tuple count
# top tables by dead tuple fraction
# top tables by total autovacuum count
# top tables by total autoanalyze count
# top tables by total buffer cache miss fraction
# top tables by approximate bloat fraction
# top indexes by total size
# top indexes by shared buffers utilization
# top indexes by total least fetch fraction
# top indexes by total buffer cache miss fraction
# top indexes by approximate bloat fraction
# top indexes by total least usage ratio
# redundant indexes
# foreign keys with no indexes

db_list_sql=$(cat <<EOF
SELECT datname
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(oid) DESC
EOF
)

tables_by_size_sql=$(cat <<EOF
SELECT n.nspname, c.relname, pg_total_relation_size(c.oid)
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
ORDER BY 3 DESC
LIMIT 5
EOF
)

tables_by_tupple_count_sql=$(cat <<EOF
SELECT n.nspname, c.relname, n_live_tup + n_dead_tup
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_stat_all_tables AS s ON s.relid = c.oid
WHERE c.relkind IN ('r', 't')
ORDER BY 3 DESC
LIMIT 5
EOF
)

tables_by_shared_buffers_sql=$(cat <<EOF
SELECT n.nspname, c.relname, count(*)
FROM pg_buffercache AS b
JOIN pg_class AS c ON c.relfilenode = b.relfilenode
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 't')
GROUP BY 1, 2 ORDER BY 3 DESC
LIMIT 5
EOF
)

tables_stats_sql=$(cat <<EOF
WITH s AS (
    SELECT * FROM pg_stat_all_tables
), tables_by_total_fetched AS (
    SELECT
        schemaname AS s, relname AS r,
        coalesce(seq_tup_read, 0) + coalesce(idx_tup_fetch, 0) AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_inserts AS (
    SELECT
        schemaname AS s, relname AS r,
        coalesce(n_tup_ins, 0) AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_updates AS (
    SELECT
        schemaname AS s, relname AS r,
        coalesce(n_tup_upd, 0) AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_deletes AS (
    SELECT
        schemaname AS s, relname AS r,
        coalesce(n_tup_del, 0) AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_seq_scan_row_count AS (
    SELECT
        schemaname AS s, relname AS r,
        seq_tup_read AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_not_hot_updates AS (
    SELECT
        schemaname AS s, relname AS r,
        n_tup_upd - n_tup_hot_upd AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_dead_tuple_count AS (
    SELECT
        schemaname AS s, relname AS r,
        n_dead_tup AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_dead_tuple_fraction AS (
    SELECT
        schemaname AS s, relname AS r,
        round(n_dead_tup::numeric / (n_dead_tup + n_live_tup), 2) AS v
    FROM s WHERE n_dead_tup + n_live_tup > 10000
    ORDER BY v DESC, n_dead_tup + n_live_tup DESC LIMIT 5
), tables_by_total_autovacuum AS (
    SELECT
        schemaname AS s, relname AS r,
        autovacuum_count AS v
    FROM s ORDER BY 3 DESC LIMIT 5
), tables_by_total_autoanalyze AS (
    SELECT
        schemaname AS s, relname AS r,
        autoanalyze_count AS v
    FROM s ORDER BY 3 DESC LIMIT 5
)
SELECT s, r, v::text, 1 FROM tables_by_total_fetched UNION ALL
SELECT s, r, v::text, 2 FROM tables_by_total_inserts UNION ALL
SELECT s, r, v::text, 3 FROM tables_by_total_updates UNION ALL
SELECT s, r, v::text, 4 FROM tables_by_total_deletes UNION ALL
SELECT s, r, v::text, 5 FROM tables_by_total_seq_scan_row_count UNION ALL
SELECT s, r, v::text, 6 FROM tables_by_total_not_hot_updates UNION ALL
SELECT s, r, v::text, 7 FROM tables_by_dead_tuple_count UNION ALL
SELECT s, r, v::text, 8 FROM tables_by_dead_tuple_fraction UNION ALL
SELECT s, r, v::text, 9 FROM tables_by_total_autovacuum UNION ALL
SELECT s, r, v::text, 10 FROM tables_by_total_autoanalyze
EOF
)

tables_iostats_sql=$(cat <<EOF
WITH s AS (
    SELECT * FROM pg_statio_all_tables
), tables_by_total_cache_miss AS (
    SELECT
        schemaname AS s, relname AS r,
        round(heap_blks_read::numeric / (heap_blks_hit + heap_blks_read), 2) AS v
    FROM s WHERE heap_blks_hit + heap_blks_read > 10000
    ORDER BY v DESC, heap_blks_hit + heap_blks_read LIMIT 5
)
SELECT s, r, v::text, 1 FROM tables_by_total_cache_miss
EOF
)

tables_by_bloat_sql=$(cat <<EOF
SELECT
    nspname, relname,
    CASE WHEN size::real > 0 THEN
        round(
            100 * (
                1 - (pure_page_count * 100 / fillfactor) / (size::real / bs)
            )::numeric, 2
        )
    ELSE 0 END AS v
FROM (
    SELECT
        nspname, relname,
        bs, size, fillfactor,
        ceil(
            reltuples * (
                max(stanullfrac) * ma * ceil(
                    (
                        ma * ceil(
                            (
                                header_width +
                                ma * ceil(count(1)::real / ma)
                            )::real / ma
                        ) + sum((1 - stanullfrac) * stawidth)
                    )::real / ma
                ) +
                (1 - max(stanullfrac)) * ma * ceil(
                    (
                        ma * ceil(header_width::real / ma) +
                        sum((1 - stanullfrac) * stawidth)
                    )::real / ma
                )
            )::real / (bs - 24)
        ) AS pure_page_count
    FROM (
        SELECT
            c.oid AS class_oid,
            n.nspname, c.relname, c.reltuples,
            23 AS header_width, 8 AS ma,
            current_setting('block_size')::integer AS bs,
            pg_relation_size(c.oid) AS size,
            coalesce((
                SELECT (
                    regexp_matches(
                        c.reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),
                '100')::real AS fillfactor
        FROM pg_class AS c
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r', 't')
    ) AS const
    LEFT JOIN pg_catalog.pg_statistic ON starelid = class_oid
    GROUP BY
        bs, class_oid, fillfactor, ma, size, reltuples, header_width,
        nspname, relname
) AS sq
WHERE pure_page_count IS NOT NULL
ORDER BY 3 DESC
LIMIT 5
EOF
)

indexes_by_size_sql=$(cat <<EOF
SELECT n.nspname, c.relname, pg_total_relation_size(c.oid)
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'i'
ORDER BY 3 DESC
LIMIT 5
EOF
)

indexes_by_shared_buffers_sql=$(cat <<EOF
SELECT n.nspname, c.relname, count(*)
FROM pg_buffercache AS b
JOIN pg_class AS c ON c.relfilenode = b.relfilenode
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'i'
GROUP BY 1, 2 ORDER BY 3 DESC
LIMIT 5
EOF
)

indexes_stats_sql=$(cat <<EOF
WITH s AS (
    SELECT * FROM pg_stat_all_indexes
), indexes_by_total_least_fetch_fraction AS (
    SELECT
        schemaname AS s, indexrelname AS r,
        round(idx_tup_fetch::numeric / (idx_tup_fetch + idx_tup_read), 2) AS v
    FROM s WHERE idx_tup_fetch + idx_tup_read > 10000
    ORDER BY v, idx_tup_fetch + idx_tup_read DESC LIMIT 5
)
SELECT s, r, v::text, 1 FROM indexes_by_total_least_fetch_fraction
EOF
)

indexes_iostats_sql=$(cat <<EOF
WITH s AS (
    SELECT * FROM pg_statio_all_indexes
), indexes_by_total_cache_miss AS (
    SELECT
        schemaname AS s, indexrelname AS r,
        round(idx_blks_read::numeric / (idx_blks_hit + idx_blks_read), 2) AS v
    FROM s WHERE idx_blks_hit + idx_blks_read > 10000
    ORDER BY v DESC, idx_blks_hit + idx_blks_read LIMIT 5
)
SELECT s, r, v::text, 1 FROM indexes_by_total_cache_miss
EOF
)

indexes_by_bloat_sql=$(cat <<EOF
-- We use COPY in the query because it contain comments
COPY (
    -- Original query has been taken from https://github.com/pgexperts/pgx_scripts
    -- WARNING: executed with a non-superuser role, the query inspect only index on tables you are granted to read.
    -- WARNING: rows with is_na = 't' are known to have bad statistics ("name" type is not supported).
    -- This query is compatible with PostgreSQL 8.2 and after
    SELECT nspname, idxname, round(100 * (relpages - est_pages_ff)::numeric / relpages, 2)
    FROM (
      SELECT coalesce(1 +
           ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0 -- ItemIdData size + computed avg size of a tuple (nulldatahdrwidth)
        ) AS est_pages,
        coalesce(1 +
           ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0
        ) AS est_pages_ff,
        bs, nspname, table_oid, tblname, idxname, relpages, fillfactor, is_na
        -- , stattuple.pgstatindex(quote_ident(nspname)||'.'||quote_ident(idxname)) AS pst, index_tuple_hdr_bm, maxalign, pagehdr, nulldatawidth, nulldatahdrwidth, reltuples -- (DEBUG INFO)
      FROM (
        SELECT maxalign, bs, nspname, tblname, idxname, reltuples, relpages, relam, table_oid, fillfactor,
          ( index_tuple_hdr_bm +
              maxalign - CASE -- Add padding to the index tuple header to align on MAXALIGN
                WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                ELSE index_tuple_hdr_bm%maxalign
              END
            + nulldatawidth + maxalign - CASE -- Add padding to the data to align on MAXALIGN
                WHEN nulldatawidth = 0 THEN 0
                WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                ELSE nulldatawidth::integer%maxalign
              END
          )::numeric AS nulldatahdrwidth, pagehdr, pageopqdata, is_na
          -- , index_tuple_hdr_bm, nulldatawidth -- (DEBUG INFO)
        FROM (
          SELECT
            i.nspname, i.tblname, i.idxname, i.reltuples, i.relpages, i.relam, a.attrelid AS table_oid,
            current_setting('block_size')::numeric AS bs, fillfactor,
            CASE -- MAXALIGN: 4 on 32bits, 8 on 64bits (and mingw32 ?)
              WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8
              ELSE 4
            END AS maxalign,
            /* per page header, fixed size: 20 for 7.X, 24 for others */
            24 AS pagehdr,
            /* per page btree opaque data */
            16 AS pageopqdata,
            /* per tuple header: add IndexAttributeBitMapData if some cols are null-able */
            CASE WHEN max(coalesce(s.null_frac,0)) = 0
              THEN 2 -- IndexTupleData size
              ELSE 2 + (( 32 + 8 - 1 ) / 8) -- IndexTupleData size + IndexAttributeBitMapData size ( max num filed per index + 8 - 1 /8)
            END AS index_tuple_hdr_bm,
            /* data len: we remove null values save space using it fractionnal part from stats */
            sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS nulldatawidth,
            max( CASE WHEN a.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0 AS is_na
          FROM pg_attribute AS a
            JOIN (
              SELECT nspname, tbl.relname AS tblname, idx.relname AS idxname, idx.reltuples, idx.relpages, idx.relam,
                indrelid, indexrelid, indkey::smallint[] AS attnum,
                coalesce(substring(
                  array_to_string(idx.reloptions, ' ')
                   from 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor
              FROM pg_index
                JOIN pg_class idx ON idx.oid=pg_index.indexrelid
                JOIN pg_class tbl ON tbl.oid=pg_index.indrelid
                JOIN pg_namespace ON pg_namespace.oid = idx.relnamespace
              WHERE pg_index.indisvalid AND tbl.relkind = 'r' AND idx.relpages > 0
            ) AS i ON a.attrelid = i.indexrelid
            JOIN pg_stats AS s ON s.schemaname = i.nspname
              AND ((s.tablename = i.tblname AND s.attname = pg_catalog.pg_get_indexdef(a.attrelid, a.attnum, TRUE)) -- stats from tbl
              OR (s.tablename = i.idxname AND s.attname = a.attname))-- stats from functionnal cols
            JOIN pg_type AS t ON a.atttypid = t.oid
          WHERE a.attnum > 0
          GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
        ) AS s1
      ) AS s2
        JOIN pg_am am ON s2.relam = am.oid WHERE am.amname = 'btree'
    ) AS sub
    -- WHERE NOT is_na
    ORDER BY 3 DESC
    LIMIT 5
) TO STDOUT (NULL 'null');
EOF
)

indexes_by_total_least_usage_sql=$(cat <<EOF
SELECT
    si.schemaname, indexrelname,
    round(
        si.idx_scan::numeric / (
            coalesce(n_tup_ins, 0) + coalesce(n_tup_upd, 0) -
            coalesce(n_tup_hot_upd, 0) + coalesce(n_tup_del, 0)
        ), 2
    )
FROM pg_stat_user_indexes AS si
JOIN pg_stat_user_tables AS st ON si.relid = st.relid
join pg_index AS i ON i.indexrelid = si.indexrelid
WHERE
    NOT indisunique AND
    (
        coalesce(n_tup_ins, 0) + coalesce(n_tup_upd, 0) -
        coalesce(n_tup_hot_upd, 0) + coalesce(n_tup_del, 0)
    ) > 0
ORDER BY 3, pg_relation_size(i.indexrelid::regclass) DESC
LIMIT 5
EOF
)

indexes_redundant_sql=$(cat <<EOF
COPY (
    -- Original query has been taken from https://github.com/pgexperts/pgx_scripts
    -- check for containment
    -- i.e. index A contains index B
    -- and both share the same first column
    -- but they are NOT identical
    WITH index_cols_ord as (
        SELECT attrelid, attnum, attname
        FROM pg_attribute
            JOIN pg_index ON indexrelid = attrelid
        WHERE indkey[0] > 0
        ORDER BY attrelid, attnum
    ),
    index_col_list AS (
        SELECT attrelid,
            array_agg(attname) as cols
        FROM index_cols_ord
        GROUP BY attrelid
    ),
    dup_natts AS (
    SELECT indrelid, indexrelid
    FROM pg_index as ind
    WHERE EXISTS ( SELECT 1
        FROM pg_index as ind2
        WHERE ind.indrelid = ind2.indrelid
        AND ( ind.indkey @> ind2.indkey
         OR ind.indkey <@ ind2.indkey )
        AND ind.indkey[0] = ind2.indkey[0]
        AND ind.indkey <> ind2.indkey
        AND ind.indexrelid <> ind2.indexrelid
    ) )
    SELECT userdex.schemaname as schema_name,
        userdex.indexrelname as index_name,
        '{' || array_to_string(cols, ', ') || '}' as index_cols
    FROM pg_stat_user_indexes as userdex
        JOIN index_col_list ON index_col_list.attrelid = userdex.indexrelid
        JOIN dup_natts ON userdex.indexrelid = dup_natts.indexrelid
        JOIN pg_indexes ON userdex.schemaname = pg_indexes.schemaname
            AND userdex.indexrelname = pg_indexes.indexname
    ORDER BY userdex.schemaname, userdex.relname, cols, userdex.indexrelname
) TO STDOUT (NULL 'null')
EOF
)

fk_without_indexes_sql=$(cat <<EOF
COPY (
    -- Original query has been taken from https://github.com/pgexperts/pgx_scripts
    -- check for FKs where there is no matching index
    -- on the referencing side
    -- or a bad index
    WITH fk_actions ( code, action ) AS (
        VALUES ( 'a', 'error' ),
            ( 'r', 'restrict' ),
            ( 'c', 'cascade' ),
            ( 'n', 'set null' ),
            ( 'd', 'set default' )
    ),
    fk_list AS (
        SELECT pg_constraint.oid as fkoid, conrelid, confrelid as parentid,
            conname, relname, nspname,
            fk_actions_update.action as update_action,
            fk_actions_delete.action as delete_action,
            conkey as key_cols
        FROM pg_constraint
            JOIN pg_class ON conrelid = pg_class.oid
            JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
            JOIN fk_actions AS fk_actions_update ON confupdtype = fk_actions_update.code
            JOIN fk_actions AS fk_actions_delete ON confdeltype = fk_actions_delete.code
        WHERE contype = 'f'
    ),
    fk_attributes AS (
        SELECT fkoid, conrelid, attname, attnum
        FROM fk_list
            JOIN pg_attribute
                ON conrelid = attrelid
                AND attnum = ANY( key_cols )
        ORDER BY fkoid, attnum
    ),
    fk_cols_list AS (
        SELECT fkoid, array_agg(attname) as cols_list
        FROM fk_attributes
        GROUP BY fkoid
    ),
    index_list AS (
        SELECT indexrelid as indexid,
            pg_class.relname as indexname,
            indrelid,
            indkey,
            indpred is not null as has_predicate,
            pg_get_indexdef(indexrelid) as indexdef
        FROM pg_index
            JOIN pg_class ON indexrelid = pg_class.oid
        WHERE indisvalid
    ),
    fk_index_match AS (
        SELECT fk_list.*,
            indexid,
            indexname,
            indkey::int[] as indexatts,
            has_predicate,
            indexdef,
            array_length(key_cols, 1) as fk_colcount,
            array_length(indkey,1) as index_colcount,
            round(pg_relation_size(conrelid)/(1024^2)::numeric) as table_mb,
            cols_list
        FROM fk_list
            JOIN fk_cols_list USING (fkoid)
            LEFT OUTER JOIN index_list
                ON conrelid = indrelid
                AND (indkey::int2[])[0:(array_length(key_cols,1) -1)] @> key_cols

    ),
    fk_perfect_match AS (
        SELECT fkoid
        FROM fk_index_match
        WHERE (index_colcount - 1) <= fk_colcount
            AND NOT has_predicate
            AND indexdef LIKE '%USING btree%'
    ),
    fk_index_check AS (
        SELECT 'no index' as issue, *, 1 as issue_sort
        FROM fk_index_match
        WHERE indexid IS NULL
        UNION ALL
        SELECT 'questionable index' as issue, *, 2
        FROM fk_index_match
        WHERE indexid IS NOT NULL
            AND fkoid NOT IN (
                SELECT fkoid
                FROM fk_perfect_match)
    ),
    parent_table_stats AS (
        SELECT fkoid, tabstats.relname as parent_name,
            (n_tup_ins + n_tup_upd + n_tup_del + n_tup_hot_upd) as parent_writes,
            round(pg_relation_size(parentid)/(1024^2)::numeric) as parent_mb
        FROM pg_stat_user_tables AS tabstats
            JOIN fk_list
                ON relid = parentid
    ),
    fk_table_stats AS (
        SELECT fkoid,
            (n_tup_ins + n_tup_upd + n_tup_del + n_tup_hot_upd) as writes,
            seq_scan as table_scans
        FROM pg_stat_user_tables AS tabstats
            JOIN fk_list
                ON relid = conrelid
    )
    SELECT nspname as schema_name,
        relname as table_name,
        conname as fk_name,
        issue,
        parent_name,
        cols_list
    FROM fk_index_check
        JOIN parent_table_stats USING (fkoid)
        JOIN fk_table_stats USING (fkoid)
    WHERE table_mb > 9
        AND ( writes > 1000
              OR parent_writes > 1000
              OR parent_mb > 10 )
    ORDER BY issue_sort, table_mb DESC, table_name, fk_name
) TO STDOUT (NULL 'null')
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$db_list))"

    for db in $db_list; do
        (
            src=$(
                $PSQL -Xc \
                    "\copy ($tables_by_size_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a tables by total size data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top tables by total size, B'
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/table']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($tables_by_tupple_count_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a tables by tupple count data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top tables by tupple count, B'
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/table']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        pg_buffercache_line=$(
            $PSQL -XAt  $db -c '\dx pg_buffercache' 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not check pg_buffercache extension'
                ['2/db']=$db
                ['3m/detail']=$result))"

        (
            if [[ -z "$pg_buffercache_line" ]]; then
                note "$(declare -pA a=(
                    ['1/message']='Can not stat shared buffers for tables, pg_buffercache is not installed'
                    ['2/db']=$db))"
            else
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
            fi
        )

        (
            src=$(
                $PSQL -Xc "\copy ($tables_stats_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a table stats data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                case "${l[3]}" in
                1)
                    message="Top tables by total fetched rows"
                    ;;
                2)
                    message="Top tables by total inserted rows"
                    ;;
                3)
                    message="Top tables by total updated rows"
                    ;;
                4)
                    message="Top tables by total deleted rows"
                    ;;
                5)
                    message="Top tables by total seq scan count"
                    ;;
                6)
                    message="Top tables by total least HOT-updated rows"
                    ;;
                7)
                    message="Top tables by dead tuple count"
                    ;;
                8)
                    message="Top tables by dead tuple fraction"
                    ;;
                9)
                    message="Top tables by total autovacuum count"
                    ;;
                10)
                    message="Top tables by total autoanalyze count"
                    ;;
                *)
                    die "$(declare -pA a=(
                        ['1/message']='Wrong number of lines in the tables stats'
                        ['2/db']=$db))"
                    ;;
                esac

                info "$(declare -pA a=(
                    ['1/message']=$message
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/table']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($tables_iostats_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a tables IO stats data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                case "${l[3]}" in
                1)
                    message="Top tables by total buffer cache miss fraction"
                    ;;
                *)
                    die "$(declare -pA a=(
                        ['1/message']='Wrong number of lines in the tables IO stats'
                        ['2/db']=$db))"
                    ;;
                esac

                info "$(declare -pA a=(
                    ['1/message']=$message
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/table']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($tables_by_bloat_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a tables by approximate bloat fraction data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top tables by approximate bloat fraction'
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/table']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($indexes_by_size_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get an indexes by size data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top indexes by size'
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/index']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            if [[ -z "$pg_buffercache_line" ]]; then
                note "$(declare -pA a=(
                    ['1/message']='Can not stat shared buffers for indexes, pg_buffercache is not installed'
                    ['2/db']=$db))"
            else
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
            fi
        )

        (
            src=$(
                $PSQL -Xc "\copy ($indexes_stats_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get an indexes stats data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                case "${l[3]}" in
                1)
                    message="Top indexes by total least fetch fraction"
                    ;;
                *)
                    die "$(declare -pA a=(
                        ['1/message']='Wrong number of lines in the indexes stats'
                        ['2/db']=$db))"
                    ;;
                esac

                info "$(declare -pA a=(
                    ['1/message']=$message
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/index']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($indexes_iostats_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get an indexes IO stats data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                case "${l[3]}" in
                1)
                    message="Top indexes by total buffer cache miss fraction"
                    ;;
                *)
                    die "$(declare -pA a=(
                        ['1/message']='Wrong number of lines in the indexes IO stats'
                        ['2/db']=$db))"
                    ;;
                esac

                info "$(declare -pA a=(
                    ['1/message']=$message
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/index']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "$indexes_by_bloat_sql" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get an indexes by approximate bloat fraction data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            while IFS=$'\t' read -r -a l; do
                info "$(declare -pA a=(
                    ['1/message']='Top indexes by approximate bloat fraction'
                    ['2/db']=$db
                    ['3/schema']=${l[0]}
                    ['4/index']=${l[1]}
                    ['5/value']=${l[2]}))"
            done <<< "$src"
        )

        (
            src=$(
                $PSQL -Xc "\copy ($indexes_by_total_least_usage_sql) to stdout (NULL 'null')" \
                    $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get an indexes by total index scans to writes ratio data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            if [[ -z "$src" ]]; then
                info "$(declare -pA a=(
                    ['1/message']='No indexes by total index scans to writes ratio'
                    ['2/db']=$db))"
            else
                while IFS=$'\t' read -r -a l; do
                    info "$(declare -pA a=(
                        ['1/message']='Top indexes by total index scans to writes ratio'
                        ['2/db']=$db
                        ['3/schema']=${l[0]}
                        ['4/index']=${l[1]}
                        ['5/value']=${l[2]}))"
                done <<< "$src"
            fi
        )

        (
            src=$($PSQL -Xc "$indexes_redundant_sql" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a redundant indexes data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            if [[ -z "$src" ]]; then
                info "$(declare -pA a=(
                    ['1/message']='No redundant indexes'
                    ['2/db']=$db))"
            else
                while IFS=$'\t' read -r -a l; do
                    info "$(declare -pA a=(
                        ['1/message']='Redundant indexes'
                        ['2/db']=$db
                        ['3/schema']=${l[0]}
                        ['4/index']=${l[1]}
                        ['5/columns']=${l[2]}))"
                done <<< "$src"
            fi
        )

        (
            src=$($PSQL -Xc "$fk_without_indexes_sql" $db 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not get a foreign keys without indexes data'
                    ['2/db']=$db
                    ['3m/detail']=$src))"

            if [[ -z "$src" ]]; then
                info "$(declare -pA a=(
                    ['1/message']='No foreign keys without indexes'
                    ['2/db']=$db))"
            else
                while IFS=$'\t' read -r -a l; do
                    info "$(declare -pA a=(
                        ['1/message']='Foreign keys without indexes'
                        ['2/db']=$db
                        ['3/schema']=${l[0]}
                        ['4/table']=${l[1]}
                        ['5/fk']=${l[2]}
                        ['6/parent_table']=${l[3]}
                        ['7/collumns']=${l[4]}))"
                done <<< "$src"
            fi
        )
    done
)

# activity by state count
# activity by state max age of transaction

sql=$(cat <<EOF
WITH c AS (
    SELECT array[
        'active', 'disabled', 'fastpath function call', 'idle',
        'idle in transaction', 'idle in transaction (aborted)', 'unknown'
    ] AS state_list
)
SELECT row_number() OVER () + 1, * FROM (
    SELECT
        regexp_replace(listed_state, E'\\\\W+', '_', 'g'),
        sum((pid IS NOT NULL)::integer),
        round(max(extract(epoch from now() - xact_start))::numeric, 2)
    FROM c CROSS JOIN unnest(c.state_list) AS listed_state
    LEFT JOIN pg_stat_activity AS p ON
        state = listed_state OR
        listed_state = 'unknown' AND state <> all(state_list)
    GROUP BY 1 ORDER BY 1
) AS s
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get an activity by state data'
            ['2m/detail']=$src))"

    declare -A activity_count=(
        ['1/message']='Activity by state count')
    declare -A activity_max_age=(
        ['1/message']='Activity by state max age of transaction, s')

    while IFS=$'\t' read -r -a l; do
        activity_count["${l[0]}/${l[1]}"]="${l[2]}"
        activity_max_age["${l[0]}/${l[1]}"]="${l[3]}"
    done <<< "$src"

    info "$(declare -p activity_count)"
    info "$(declare -p activity_max_age)"

)

# lock waiting activity count
# lock waiting activity age min, max

sql=$(cat <<EOF
SELECT
    count(1),
    round(min(extract(epoch from now() - xact_start))),
    round(max(extract(epoch from now() - xact_start)))
FROM pg_stat_activity WHERE waiting
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a waiting activity data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Lock waiting activity count'
        ['2/value']=${l[0]}))"
    info "$(declare -pA a=(
        ['1/message']='Lock waiting activity age, s'
        ['2/min']=${l[1]}
        ['3/max']=${l[2]}))"
)

# deadlocks count
# block operations count for buffer cache hit, read
# buffer cache hit fraction
# temp files count
# temp data written size
# transactions count committed and rolled back
# tuple extraction count fetched and returned
# tuple operations count inserted, updated and deleted

sql=$(cat <<EOF
SELECT
    extract(epoch from now())::integer,
    sum(deadlocks),
    sum(blks_hit), sum(blks_read),
    sum(temp_files), sum(temp_bytes),
    sum(xact_commit), sum(xact_rollback),
    sum(tup_fetched), sum(tup_returned),
    sum(tup_inserted), sum(tup_updated), sum(tup_deleted)
FROM pg_stat_database
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['timestamp']="${l[0]}"
        ['deadlocks']="${l[1]}"
        ['blks_hit']="${l[2]}"
        ['blks_read']="${l[3]}"
        ['temp_files']="${l[4]}"
        ['temp_bytes']="${l[5]}"
        ['xact_commit']="${l[6]}"
        ['xact_rollback']="${l[7]}"
        ['tup_fetched']="${l[8]}"
        ['tup_returned']="${l[9]}"
        ['tup_inserted']="${l[10]}"
        ['tup_updated']="${l[11]}"
        ['tup_deleted']="${l[12]}")

    regex='declare -A database_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/database_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous database stat record in the snapshot file'))"
    else
        eval "$snap_src"

        interval=$((${stat['timestamp']} - ${snap['timestamp']}))

        deadlocks=$(( ${stat['deadlocks']} - ${snap['deadlocks']} ))
        blks_hit=$(( ${stat['blks_hit']} - ${snap['blks_hit']} ))
        blks_read=$(( ${stat['blks_read']} - ${snap['blks_read']} ))
        blks_hit_s=$(( $blks_hit / $interval ))
        blks_read_s=$(( $blks_read / $interval ))
        hit_fraction=$(
            (( $blks_hit + $blks_read > 0 )) && \
            echo "scale=2; $blks_hit / ($blks_hit + $blks_read)" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')
        temp_files=$(( ${stat['temp_files']} - ${snap['temp_files']} ))
        temp_bytes=$(( ${stat['temp_bytes']} - ${snap['temp_bytes']} ))
        xact_commit=$(( ${stat['xact_commit']} - ${snap['xact_commit']} ))
        xact_rollback=$(( ${stat['xact_rollback']} - ${snap['xact_rollback']} ))
        tup_fetched=$(( ${stat['tup_fetched']} - ${snap['tup_fetched']} ))
        tup_returned=$(( ${stat['tup_returned']} - ${snap['tup_returned']} ))
        tup_inserted=$(( ${stat['tup_inserted']} - ${snap['tup_inserted']} ))
        tup_updated=$(( ${stat['tup_updated']} - ${snap['tup_updated']} ))
        tup_deleted=$(( ${stat['tup_deleted']} - ${snap['tup_deleted']} ))

        info "$(declare -pA a=(
            ['1/message']='Deadlocks count'
            ['2/value']=$deadlocks))"

        info "$(declare -pA a=(
            ['1/message']='Block operations count, /s'
            ['2/buffer_cache_hit']=$blks_hit_s
            ['3/read']=$blks_read_s))"

        info "$(declare -pA a=(
            ['1/message']='Buffer cache hit fraction'
            ['2/value']=$hit_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Temp files count'
            ['2/value']=$temp_files))"

        info "$(declare -pA a=(
            ['1/message']='Temp data written size, B'
            ['2/value']=$temp_bytes))"

        info "$(declare -pA a=(
            ['1/message']='Transaction count'
            ['2/commit']=$xact_commit
            ['3/rollback']=$xact_rollback))"

        info "$(declare -pA a=(
            ['1/message']='Tuple extraction count'
            ['2/fetched']=$tup_fetched
            ['3/returned']=$tup_returned))"

        info "$(declare -pA a=(
            ['1/message']='Tuple operations count'
            ['2/inserted']=$tup_inserted
            ['3/updated']=$tup_updated
            ['4/deleted']=$tup_deleted))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the database stat snapshot'
            ['2m/detail']=$error))"
)

# locks by granted count

sql=$(cat <<EOF
SELECT sum((NOT granted)::integer), sum(granted::integer) FROM pg_locks
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a locks data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Locks by granted count'
        ['2/not_granted']=${l[0]}
        ['3/granted']=${l[1]}))"
)

# prepared transaction count
# prepared transaction age min, max

sql=$(cat <<EOF
SELECT count(1), min(prepared), max(prepared)
FROM pg_prepared_xacts
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a prepared transaction data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Prepared transactions count'
        ['2/value']=${l[0]}))"

    info "$(declare -pA a=(
        ['1/message']='Prepared transaction age, s'
        ['2/min']=${l[1]}
        ['3/max']=${l[2]}))"
)

# bgwritter checkpoint count scheduled, requested
# bgwritter checkpoint time write, sync
# bgwritter buffers written by method count checkpoint, bgwriter and backends
# bgwritter event count maxwritten stops, backend fsyncs

sql=$(cat <<EOF
SELECT
    checkpoints_timed, checkpoints_req,
    checkpoint_write_time, checkpoint_sync_time,
    buffers_checkpoint, buffers_clean, buffers_backend,
    maxwritten_clean, buffers_backend_fsync
FROM pg_stat_bgwriter
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a bgwriter stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['chk_timed']="${l[0]}"
        ['chk_req']="${l[1]}"
        ['chk_w_time']="${l[2]}"
        ['chk_s_time']="${l[3]}"
        ['buf_chk']="${l[4]}"
        ['buf_cln']="${l[5]}"
        ['buf_back']="${l[6]}"
        ['maxw']="${l[7]}"
        ['back_fsync']="${l[8]}")

    regex='declare -A bgwriter_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/bgwriter_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous bgwriter stat record in the snapshot file'))"
    else
        eval "$snap_src"

        chk_timed=$(( ${stat['chk_timed']} - ${snap['chk_timed']} ))
        chk_req=$(( ${stat['chk_req']} - ${snap['chk_req']} ))
        chk_w_time=$(( ${stat['chk_w_time']} - ${snap['chk_w_time']} ))
        chk_s_time=$(( ${stat['chk_s_time']} - ${snap['chk_s_time']} ))
        buf_chk=$(( ${stat['buf_chk']} - ${snap['buf_chk']} ))
        buf_cln=$(( ${stat['buf_cln']} - ${snap['buf_cln']} ))
        buf_back=$(( ${stat['buf_back']} - ${snap['buf_back']} ))
        maxw=$(( ${stat['maxw']} - ${snap['maxw']} ))
        back_fsync=$(( ${stat['back_fsync']} - ${snap['back_fsync']} ))

        info "$(declare -pA a=(
            ['1/message']='Bgwriter checkpoint count'
            ['2/scheduled']=$chk_timed
            ['3/requested']=$chk_req))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter checkpoint time, ms'
            ['2/write']=$chk_w_time
            ['3/sync']=$chk_s_time))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter buffers written by method count'
            ['2/checkpoint']=$buf_chk
            ['3/backend']=$buf_back))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter event count'
            ['2/maxwritten_stops']=$maxw
            ['3/backend_fsyncs']=$back_fsync))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the bgwriter stat snapshot'
            ['2m/detail']=$error))"
)

# shared buffers distribution

sql=$(cat <<EOF
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

(
    pg_buffercache_line=$(
        $PSQL -XAt -c '\dx pg_buffercache' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not check pg_buffercache extension'
            ['2m/detail']=$result))"

    if [[ -z "$pg_buffercache_line" ]]; then
        note "$(declare -pA a=(
            ['1/message']='Can not stat shared buffers for distribution, pg_buffercache is not instaled'))"
    else
        src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a buffercache data'
                ['2m/detail']=$src))"

        declare -A stat=(
            ['1/message']='Shared buffers usage count distribution')

        while IFS=$'\t' read -r -a l; do
            stat["${l[0]}/${l[1]}"]="${l[2]}"
        done <<< "$src"

        info "$(declare -p stat)"
    fi
)

# conflict with recovery count by type

sql=$(cat <<EOF
SELECT
    sum(confl_tablespace), sum(confl_lock), sum(confl_snapshot),
    sum(confl_bufferpin), sum(confl_deadlock)
FROM pg_stat_database_conflicts
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database conflicts stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['tablespace']="${l[0]}"
        ['lock']="${l[1]}"
        ['snapshot']="${l[2]}"
        ['bufferpin']="${l[3]}"
        ['deadlock']="${l[4]}")

    regex='declare -A database_conflicts_stat='

    snap_src=$(
        grep "$regex" $STAT_POSTGRES_FILE \
            | sed 's/database_conflicts_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous database conflicts stat record in the snapshot file'))"
    else
        eval "$snap_src"

        tablespace=$(( ${stat['tablespace']} - ${snap['tablespace']} ))
        lock=$(( ${stat['lock']} - ${snap['lock']} ))
        snapshot=$(( ${stat['snapshot']} - ${snap['snapshot']} ))
        bufferpin=$(( ${stat['bufferpin']} - ${snap['bufferpin']} ))
        deadlock=$(( ${stat['deadlock']} - ${snap['deadlock']} ))

        info "$(declare -pA a=(
            ['1/message']='Conflict with recovery count by type'
            ['2/tablespace']=$tablespace
            ['3/lock']=$lock
            ['4/snapshot']=$snapshot
            ['5/bufferpin']=$bufferpin
            ['6/deadlock']=$deadlock))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the database conflicts stat snapshot'
            ['2m/detail']=$error))"
)

# replication connection count

sql=$(cat <<EOF
SELECT count(1) FROM pg_stat_replication
EOF
)

(
    src=$($PSQL -XAt -P 'null=null' -c "$sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a replication stat data'
            ['2m/detail']=$src))"

    info "$(declare -pA a=(
        ['1/message']='Replication connections count'
        ['2/value']=$src))"
)

# seq scan change fraction value
# hot update change fraction value
# dead and live tuple count dead, live
# dead tuple fraction value
# vacuum and analyze counts vacuum, analyze, autovacuum, autoanalyze

sql=$(cat <<EOF
SELECT
    sum(seq_scan), sum(idx_scan),
    sum(n_tup_hot_upd), sum(n_tup_upd),
    sum(n_dead_tup), sum(n_live_tup),
    sum(vacuum_count), sum(analyze_count),
    sum(autovacuum_count), sum(autoanalyze_count)
FROM pg_stat_all_tables
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$db_list))"

    declare -A stat

    for db in $db_list; do
        src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a tables stat data'
                ['2/db']=$db
                ['3m/detail']=$src))"

        IFS=$'\t' read -r -a l <<< "$src"

        stat['seq_scan']=$(( ${stat['seq_scan']:-0} + ${l[0]} ))
        stat['idx_scan']=$(( ${stat['idx_scan']:-0} + ${l[1]} ))
        stat['n_tup_hot_upd']=$(( ${stat['n_tup_hot_upd']:-0} + ${l[2]} ))
        stat['n_tup_upd']=$(( ${stat['n_tup_upd']:-0} + ${l[3]} ))
        n_dead_tup=$(( ${n_dead_tup:-0} + ${l[4]} ))
        n_live_tup=$(( ${n_live_tup:-0} + ${l[5]} ))
        stat['vacuum']=$(( ${stat['vacuum']:-0} + ${l[6]} ))
        stat['analyze']=$(( ${stat['analyze']:-0} + ${l[7]} ))
        stat['autovacuum']=$(( ${stat['autovacuum']:-0} + ${l[8]} ))
        stat['autoanalyze']=$(( ${stat['autoanalyze']:-0} + ${l[9]} ))
    done

    regex='declare -A tables_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/tables_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous tables stat record in the snapshot file'))"
    else
        eval "$snap_src"

        seq_scan=$(( ${stat['seq_scan']} - ${snap['seq_scan']} ))
        idx_scan=$(( ${stat['idx_scan']} - ${snap['idx_scan']} ))
        n_tup_hot_upd=$(( ${stat['n_tup_hot_upd']} - ${snap['n_tup_hot_upd']} ))
        n_tup_upd=$(( ${stat['n_tup_upd']} - ${snap['n_tup_upd']} ))
        vacuum=$(( ${stat['vacuum']} - ${snap['vacuum']} ))
        analyze=$(( ${stat['analyze']} - ${snap['analyze']} ))
        autovacuum=$(( ${stat['autovacuum']} - ${snap['autovacuum']} ))
        autoanalyze=$(( ${stat['autoanalyze']} - ${snap['autoanalyze']} ))

        seq_scan_fraction=$(
            (( $seq_scan + $idx_scan > 0 )) &&
            echo "scale=2; $seq_scan / ($seq_scan + $idx_scan)" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')
        hot_update_fraction=$(
            (( $n_tup_upd > 0 )) &&
            echo "scale=2; $n_tup_hot_upd / $n_tup_upd" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')
        dead_tuple_fraction=$(
            (( $n_dead_tup + $n_live_tup > 0 )) &&
            echo "scale=2; $n_dead_tup / ($n_dead_tup + $n_live_tup)" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')

        info "$(declare -pA a=(
            ['1/message']='Seq scan fraction'
            ['2/value']=$seq_scan_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Hot update fraction'
            ['2/value']=$hot_update_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Dead and live tuple numer'
            ['2/dead']=$n_dead_tup
            ['3/live']=$n_live_tup))"

        info "$(declare -pA a=(
            ['1/message']='Dead tuple fraction'
            ['2/value']=$dead_tuple_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Vacuum and analyze counts'
            ['2/vacuum']=$vacuum
            ['3/analyze']=$analyze
            ['4/autovacuum']=$autovacuum
            ['5/autoanalyze']=$autoanalyze))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the all tables stat snapshot'
            ['2m/detail']=$error))"
)
