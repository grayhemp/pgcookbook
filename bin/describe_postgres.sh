#!/bin/bash

# describe_postgres.sh - provides details about a PostgreSQL instance.
#
# Prints out version, tablespaces, custom settings, etc.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# version information

(
    src=$($PSQL -XAtc 'SELECT version()' 2>&1) ||
        die "Can not get a version data: $src."

    regex='^(.+) on (\S+),'

    [[ $src =~ $regex ]] ||
        die "Can not match the version data: $src."

    version=${BASH_REMATCH[1]}
    arch=${BASH_REMATCH[2]}

    info "Version information: version $version, arch $arch."
)

# tablespaces

(
    src_list=$($PSQL -XAtc '\db' -F ' ' 2>&1) ||
        die "Can not get a tablespace data: $src."

    while read src; do
        (
            regex='^(\S+) (\S+)( (\S+))?'

            [[ $src =~ $regex ]] ||
                die "Can not match the tablespace data: $src."

            name=${BASH_REMATCH[1]}
            owner=${BASH_REMATCH[2]}
            location=${BASH_REMATCH[4]:-'N/A'}

            info "Tablespace $name: owner $owner, location $location."
        )
    done <<< "$src_list"
)

# symlinks

(
    data_dir=$($PSQL -XAtc 'SHOW data_directory' 2>&1) ||
        die "Can not get a data dir: $data_dir."

    src_list=$(ls -l $data_dir 2>&1) ||
        die "Can not list the data dir: $src_list."
    src_list=$(
        echo "$src_list" | grep -E '^l' | sed -r 's/^(\S+\s+){8}//')

    if [ ! -z "$src_list" ]; then
        while read src; do
            (
                regex='^(\S+) -> (.+)'

                [[ $src =~ $regex ]] ||
                    die "Can not match the symlinks data: $src."

                name=${BASH_REMATCH[1]}
                dest=${BASH_REMATCH[2]}

                info "Symlink $name: destination $dest."
            )
        done <<< "$src_list"
    else
        info "No symlinks found."
    fi
)

# custom settings

sql=$(cat <<EOF
SELECT name, setting
FROM pg_settings WHERE
    setting IS DISTINCT FROM reset_val AND
    NOT (
        name = 'archive_command' AND
        setting = '(disabled)' AND
        reset_val = '') AND
    NOT (
        name = 'transaction_isolation' AND
        setting = 'read committed' AND
        reset_val = 'default');
EOF
)

(

    src=$($PSQL -XAt -F ' ' -R ', ' -c "$sql" 2>&1) ||
        die "Can not get a settings data: $src."

    info "Custom settings: $src."
)

# top databases by size

sql=$(cat <<EOF
SELECT datname, pg_database_size(oid)
FROM pg_database
WHERE datallowconn
ORDER BY 2 DESC
LIMIT 5;
EOF
)

(

    src=$($PSQL -XAt -F ' ' -R ', ' -c "$sql" 2>&1) ||
        die "Can not get a database data: $src."

    info "Top databases by size, B: $src."
)

# top databases by shared buffers utilization

sql=$(cat <<EOF
SELECT datname, count(*)
FROM pg_buffercache AS b
JOIN pg_database AS d ON b.reldatabase = d.oid
WHERE d.datallowconn
GROUP BY 1 ORDER BY 2 DESC
LIMIT 5;
EOF
)

(
    extension_line=$($PSQL -XAtc '\dx pg_buffercache' 2>&1) ||
        die "Can not check pg_buffercache extension: $extension_line."

    if [[ -z "$extension_line" ]]; then
        note "Can not stat shared buffers for databases," \
             "pg_buffercache is not installed."
    else
        src=$($PSQL -XAt -R ', ' -F ' ' -P 'null=N/A' -c "$sql" 2>&1) ||
            die "Can not get a buffercache data for databases: $src."

        info "Top databases by shared buffers utilization: $src."
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
LIMIT 5;
EOF
)

tables_by_tupple_count_sql=$(cat <<EOF
SELECT n.nspname, c.relname, n_live_tup + n_dead_tup
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_stat_all_tables AS s ON s.relid = c.oid
WHERE c.relkind IN ('r', 't')
ORDER BY 3 DESC
LIMIT 5;
EOF
)

tables_by_shared_buffers_sql=$(cat <<EOF
SELECT n.nspname, c.relname, count(*)
FROM pg_buffercache AS b
JOIN pg_class AS c ON c.relfilenode = b.relfilenode
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 't')
GROUP BY 1, 2 ORDER BY 3 DESC
LIMIT 5;
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
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_fetched UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_inserts UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_updates UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_deletes UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_seq_scan_row_count UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_not_hot_updates UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_dead_tuple_count UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_dead_tuple_fraction UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_autovacuum UNION ALL
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_autoanalyze UNION ALL
SELECT null WHERE false
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
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM tables_by_total_cache_miss UNION ALL
SELECT NULL WHERE FALSE
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
LIMIT 5;
EOF
)

indexes_by_size_sql=$(cat <<EOF
SELECT n.nspname, c.relname, pg_total_relation_size(c.oid)
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'i'
ORDER BY 3 DESC
LIMIT 5;
EOF
)

indexes_by_shared_buffers_sql=$(cat <<EOF
SELECT n.nspname, c.relname, count(*)
FROM pg_buffercache AS b
JOIN pg_class AS c ON c.relfilenode = b.relfilenode
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'i'
GROUP BY 1, 2 ORDER BY 3 DESC
LIMIT 5;
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
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM indexes_by_total_least_fetch_fraction UNION ALL
SELECT NULL WHERE FALSE
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
SELECT array_to_string(array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
FROM indexes_by_total_cache_miss UNION ALL
SELECT NULL WHERE FALSE
EOF
)

indexes_by_bloat_sql=$(cat <<EOF
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
LIMIT 5;
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
WHERE NOT indisunique
ORDER BY 3 DESC, pg_relation_size(i.indexrelid::regclass) DESC
LIMIT 5;
EOF
)

indexes_redundant_sql=$(cat <<EOF
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
ORDER BY userdex.schemaname, userdex.relname, cols, userdex.indexrelname;
EOF
)

fk_without_indexes_sql=$(cat <<EOF
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
ORDER BY issue_sort, table_mb DESC, table_name, fk_name;
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "Can not get a database list: $src."

    for db in $db_list; do
        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$tables_by_size_sql" 2>&1) ||
                die "Can not get a tables by total size data for $db: $src."

            info "Top tables by total size for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$tables_by_tupple_count_sql" \
                    2>&1) ||
                die "Can not get a tables by tupple count data for $db: $src."

            info "Top tables by tupple count for $db, B: $src."
        )

        pg_buffercache_line=$(
            echo $(
                $PSQL -XAt  $db -c '\dx pg_buffercache' 2>&1) ||
                die "Can not check pg_buffercache extension for $db:" \
                    "$pg_buffercache_line."
        )

        (
            if [[ -z "$pg_buffercache_line" ]]; then
                note "Can not stat shared buffers for tables for $db," \
                     "pg_buffercache is not installed."
            else
                src=$(
                    $PSQL -XAt -R ', ' -F ' ' $db \
                        -c "$tables_by_shared_buffers_sql" 2>&1) ||
                    die "Can not get a buffercache data for tables for $db:" \
                        "$src."

                info "Top tables by shared buffers utilization for $db: $src."
            fi
        )

        (
            src_list=$($PSQL -XAt $db -c "$tables_stats_sql" 2>&1) ||
                die "Can not get a tables stats data for $db: $src_list."

            line=1
            while read src; do
                case $line in
                1)
                    info "Top tables by total fetched rows for $db: $src."
                    ;;
                2)
                    info "Top tables by total inserted rows for $db: $src."
                    ;;
                3)
                    info "Top tables by total updated rows for $db: $src."
                    ;;
                4)
                    info "Top tables by total deleted rows for $db: $src."
                    ;;
                5)
                    info "Top tables by total seq scan count for $db: $src."
                    ;;
                6)
                    info "Top tables by total least HOT-updated rows for $db:" \
                         "$src."
                    ;;
                7)
                    info "Top tables by dead tuple count for $db: $src."
                    ;;
                8)
                    info "Top tables by dead tuple fraction for $db: $src."
                    ;;
                9)
                    info "Top tables by total autovacuum count for $db: $src."
                    ;;
                10)
                    info "Top tables by total autoanalyze count for $db: $src."
                    ;;
                *)
                    die "Wrong number of lines in the tables stats for $db."
                    ;;
                esac
                line=$(( $line + 1 ))
            done <<< "$src_list"
        )

        (
            src_list=$($PSQL -XAt $db -c "$tables_iostats_sql" 2>&1) ||
                die "Can not get a tables IO stats data for $db: $src_list."

            line=1
            while read src; do
                case $line in
                1)
                    info "Top tables by total buffer cache miss fraction for" \
                         "$db: $src."
                    ;;
                *)
                    die "Wrong number of lines in the tables stats for $db."
                    ;;
                esac
                line=$(( $line + 1 ))
            done <<< "$src_list"
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$tables_by_bloat_sql" \
                    2>&1) ||
                die "Can not get a tables by bloat fraction data for $db: $src."

            info "Top tables by approximate bloat fraction for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$indexes_by_size_sql" 2>&1) ||
                die "Can not get an indexes by size data for $db: $src."

            info "Top indexes by size for $db, B: $src."
        )

        (
            if [[ -z "$pg_buffercache_line" ]]; then
                note "Can not stat shared buffers for indexes for $db," \
                     "pg_buffercache is not installed."
            else
                src=$(
                    $PSQL -XAt -R ', ' -F ' ' $db \
                        -c "$indexes_by_shared_buffers_sql" 2>&1) ||
                    die "Can not get a buffercache data for indexes for $db:" \
                        "$src."

                info "Top indexes by shared buffers utilization for $db: $src."
            fi
        )

        (
            src_list=$($PSQL -XAt $db -c "$indexes_stats_sql" 2>&1) ||
                die "Can not get an indexes stats data for $db: $src_list."

            line=1
            while read src; do
                case $line in
                1)
                    info "Top indexes by total least fetch fraction for" \
                         "$db: $src."
                    ;;
                *)
                    die "Wrong number of lines in the indexes stats for $db."
                    ;;
                esac
                line=$(( $line + 1 ))
            done <<< "$src_list"
        )

        (
            src_list=$($PSQL -XAt $db -c "$indexes_iostats_sql" 2>&1) ||
                die "Can not get an indexes IO stats data for $db: $src_list."

            line=1
            while read src; do
                case $line in
                1)
                    info "Top indexes by total buffer cache miss fraction for" \
                         "$db: $src."
                    ;;
                *)
                    die "Wrong number of lines in the tables stats for $db."
                    ;;
                esac
                line=$(( $line + 1 ))
            done <<< "$src_list"
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$indexes_by_bloat_sql" \
                    2>&1) ||
                die "Can not get an indexes by bloat fraction data for $db:" \
                    "$src."

            info "Top indexes by approximate bloat fraction for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db \
                      -c "$indexes_by_total_least_usage_sql" 2>&1) ||
                die "Can not get an indexes by usage ratio data for $db:" \
                    "$src."

            info "Top indexes by total least usage ratio for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db \
                      -c "$indexes_redundant_sql" 2>&1) ||
                die "Can not get a redundant indexes data for $db: $src."

            info "Redundant indexes for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db \
                      -c "$fk_without_indexes_sql" 2>&1) ||
                die "Can not get a foreign keys without indexes data for $db:" \
                    "$src."

            info "Foreign keys without indexes for $db, B: $src."
        )
    done
)
