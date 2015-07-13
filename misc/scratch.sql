-- archive_tables.sh

\c postgres
DROP DATABASE IF EXISTS dbname1;
DROP DATABASE IF EXISTS dbname2;
--
CREATE DATABASE dbname1;
CREATE DATABASE dbname2;
--
\c dbname1
--
DO $$
BEGIN
    EXECUTE format(
        'CREATE TABLE table1_%s (t text)',
        to_char(now() - '12 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table1_%s (t text)',
        to_char(now() - '13 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table2_%s (t text)',
        to_char(now() - '10 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table2_%s (t text)',
        to_char(now() - '14 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_%s (t text)',
        to_char(now() - '24 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_%s (t text)',
        to_char(now() - '25 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_exc_%s (t text)',
        to_char(now() - '36 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_exc_%s (t text)',
        to_char(now() - '37 months'::interval, 'YYYYMM'));
END $$;
--
\c dbname2
--
DO $$
BEGIN
    EXECUTE format(
        'CREATE TABLE table1_%s (t text)',
        to_char(now() - '12 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table1_%s (t text)',
        to_char(now() - '13 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table2_%s (t text)',
        to_char(now() - '10 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table2_%s (t text)',
        to_char(now() - '14 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_%s (t text)',
        to_char(now() - '24 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_%s (t text)',
        to_char(now() - '25 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_exc_%s (t text)',
        to_char(now() - '36 months'::interval, 'YYYYMM'));
    EXECUTE format(
        'CREATE TABLE table3_exc_%s (t text)',
        to_char(now() - '37 months'::interval, 'YYYYMM'));
END $$;

/*

rm -rf /mnt/archive/parts
mkdir -p /mnt/archive/parts

bash bin/archive_tables.sh

ls -l /mnt/archive/parts/*

*/

-- commit_schema.sh

\c postgres
DROP DATABASE IF EXISTS dbname1;
--
CREATE DATABASE dbname1;
--
DROP DATABASE IF EXISTS dbname2;
--
CREATE DATABASE dbname2;
--
\c dbname1
--
CREATE TABLE table1 AS
SELECT i AS id
FROM generate_series(1, 5) i;
--
\c dbname2
--
CREATE TABLE table2 AS
SELECT i AS id
FROM generate_series(1, 5) i;
--
CREATE SCHEMA pgq;
--
CREATE SCHEMA partitions;
--
CREATE TABLE partitions.part1 (t text);

/*

rm -rf /tmp/_repo
rm -rf /mnt/archive/repo
rm /tmp/_repo_id_rsa
mkdir -p /tmp/_repo
git -C /tmp/_repo init --bare
git clone /tmp/_repo /mnt/archive/repo
touch /mnt/archive/repo/file
git -C /mnt/archive/repo add .
git -C /mnt/archive/repo commit -m 'Initial commit.'
git -C /mnt/archive/repo push origin master
ssh-keygen -t rsa -f /tmp/_repo_id_rsa

SCHEMA_SSH_KEY='/tmp/_repo_id_rsa' bash bin/commit_schema.sh

*/

\c dbname1
--
DROP SCHEMA schema2;

/*

bash bin/commit_schema.sh

git -C /mnt/archive/repo log -p

*/

-- describe_pgbouncer.sh

/*

PORT=6432 bash bin/describe_pgbouncer.sh

*/

-- describe_postgres.sh

/*

bash bin/describe_postgres.sh

*/

-- describe_skytools.sh

/*

bash bin/describe_skytools.sh

*/

-- describe_system.sh

/*

bash bin/describe_system.sh

*/

-- manage_dumps.sh

\c postgres
DROP DATABASE IF EXISTS dbname1;
--
CREATE DATABASE dbname1;
--
\c dbname1
--
CREATE TABLE table1 AS
SELECT i AS id
FROM generate_series(1, 5) i;

/*

bash bin/manage_dumps.sh

*/

-- manage_pitr.sh

/*

PITR_WAL=true bash bin/manage_pitr.sh

# And in the other terminal
PITR_WAL=true bash bin/manage_pitr.sh # it shouldn't start

*/

CREATE TABLE t (t text);
INSERT INTO t SELECT i FROM generate_series(1,1000000) as i;

/*

bash bin/manage_pitr.sh
mv /mnt/archive/basebackups/20141028 /mnt/archive/basebackups/20141026

*/

INSERT INTO t SELECT i FROM generate_series(1,1000000) as i;

/*

bash bin/manage_pitr.sh
mv /mnt/archive/basebackups/20141028 /mnt/archive/basebackups/20141027

*/

INSERT INTO t SELECT i FROM generate_series(1,1000000) as i;

/*

bash bin/manage_pitr.sh # should delete 20141026 and clean pre-20141027 WAL

*/

-- process_until_0.sh

DROP TABLE IF EXISTS test_process_until_0;
CREATE TABLE test_process_until_0 (i integer);

/*

bash bin/process_until_0.sh <<EOF
INSERT INTO test_process_until_0 SELECT g.i
FROM generate_series(0, 99) AS g(i)
LEFT JOIN test_process_until_0 AS t ON t.i = g.i
WHERE t.i IS NULL
LIMIT 10;
EOF

bash bin/process_until_0.sh <<EOF
UPDATE test_process_until_0 SET i = i + 100
WHERE i IN (SELECT i FROM test_process_until_0 WHERE i < 100 LIMIT 10);
EOF

bash bin/process_until_0.sh <<EOF
DELETE FROM test_process_until_0
WHERE i IN (SELECT i FROM test_process_until_0 LIMIT 10);
EOF

*/

-- refresh_matviews.sh

\c postgres
--
DROP DATABASE IF EXISTS dbname1;
--
CREATE DATABASE dbname1;
--
DROP DATABASE IF EXISTS dbname2;
--
CREATE DATABASE dbname2;
--
\c dbname1
--
CREATE MATERIALIZED VIEW x AS SELECT 1 AS i;
CREATE MATERIALIZED VIEW y AS SELECT * FROM x;
CREATE INDEX y_i ON y (i);
--
\c dbname2
--
CREATE MATERIALIZED VIEW a AS SELECT 1 AS i;
CREATE MATERIALIZED VIEW b AS SELECT * FROM a;
CREATE MATERIALIZED VIEW c AS SELECT * FROM b;
CREATE MATERIALIZED VIEW d AS SELECT * FROM a;
CREATE MATERIALIZED VIEW e AS SELECT 1 AS i;
CREATE INDEX a_i ON a (i);
CREATE INDEX c_i ON c (i);
CREATE INDEX e_i ON e (i);

/*

bash bin/refresh_matviews.sh

*/

-- replica_lag.sh

/*

bash bin/replica_lag.sh

LAG_DSN='host=nohost' bash bin/replica_lag.sh

*/

-- restore_dump.sh

\c postgres
DROP DATABASE IF EXISTS dbname1;
--
CREATE DATABASE dbname1;
--
\c dbname1
--
CREATE TABLE table1 AS
SELECT i AS id
FROM generate_series(1, 5) i;
--
CREATE TABLE log1 AS
SELECT i AS id
FROM generate_series(1, 5) i;
--
CREATE TABLE data1 AS
SELECT i AS id, i % 2 AS status
FROM generate_series(1, 5) i;
CREATE FUNCTION data1_err() RETURNS trigger LANGUAGE 'plpgsql' AS $$
BEGIN RAISE EXCEPTION 'Boom!'; END $$;
CREATE TRIGGER data1_err_t BEFORE INSERT ON data1 FOR EACH ROW
EXECUTE PROCEDURE data1_err();
--
CREATE TABLE pres1 AS
SELECT i AS id
FROM generate_series(1, 5) i;

/*

bash bin/manage_dumps.sh

*/

INSERT INTO pres1 VALUES(6);
DELETE FROM pres1 WHERE id = 5;

/*

RESTORE_DBNAME=dbname1 bash bin/restore_dump.sh

*/

SELECT * FROM table1;
SELECT * FROM log1;
SELECT * FROM data1;
SELECT * FROM pres1;

-- ssh_tunnel.sh

/*

bash bin/ssh_tunnel.sh

*/

-- stat_pgbouncer.sh

/*

PORT=6432 bash bin/stat_pgbouncer.sh

*/

-- stat_postgres_buffercache.sh

/*

bash bin/stat_postgres_buffercache.sh

*/

-- stat_postgres_objects.sh

/*

bash bin/stat_postgres_objects.sh

*/

-- stat_postgres.sh

/*

bash bin/stat_postgres.sh

*/

-- stat_skytools.sh

/*

bash bin/stat_skytools.sh

*/

-- stat_statements.sh

WITH def AS (
SELECT $$
some /* thing */ has /* been
carefully
written
somewhere
here */ -- yep
and -- here
also
$$::text AS s
)
SELECT
    regexp_replace(
        regexp_replace(s, '--(.*?$)', '-- [comment]', 'gm'),
        E'\\/\\*(.*?)\\*\\/', '/* [comment] */', 'gs')
FROM def;

TRUNCATE TABLE stat_statements;

SELECT pg_stat_statements_reset();

SELECT column1, /* 12 */ column2 -- 12
FROM (VALUES (1, 2)) AS s; -- 34 "abc"
-- 56

SELECT column1, /* 56 */ column2 -- 56
FROM (VALUES (1, 2)) AS s; -- 78
-- 90

SELECT * FROM pg_stat_statements WHERE query ~ 'column1';

INSERT INTO public.stat_statements
SELECT '', now(), * FROM pg_stat_statements;

DELETE FROM stat_statements WHERE query !~ 'column1';

SELECT * FROM stat_statements;

SELECT public.stat_statements_get_report(
    '', now()::date - 1, now()::date + 1, 10, 0);

INSERT INTO public.stat_statements
SELECT 'host=host3', now(), * FROM pg_stat_statements;

INSERT INTO public.stat_statements
SELECT 'host=host4', now(), * FROM dblink(
    'host=host4 dbname=dbname1',
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

SELECT * FROM dblink(
    'host=host4 dbname=dbname1',
    'SELECT pg_stat_statements_reset()'
) AS s(t text);

SELECT public.stat_statements_get_report(
    'host=host4', now()::date, now()::date + 1, 2, 2);

DELETE FROM public.stat_statements WHERE created < now() - '7 days'::interval;

/*

STAT_SNAPSHOT=true bash bin/stat_statements.sh

bash bin/stat_statements.sh

# json format test
LOG_FORMAT=json STAT_N=10000 STAT_SINCE=$(date -I --date='-100 day') \
    bash bin/stat_statements.sh \
    | while read -r v; do echo "$v" | json_pp ; done >/dev/null

LOG_FORMAT=json PORT=123 bash bin/stat_statements.sh 2>&1 | json_pp

*/

-- stat_system.sh

/*

bash bin/stat_system.sh

*/

-- terminate_activity.sh

/*

(
    flock -xn 543 || exit 0
    trap "rm -f $TERMINATE_PID_FILE" EXIT
    echo $(cut -d ' ' -f 4 /proc/self/stat) >$TERMINATE_PID_FILE
    ...
)

*/

/*

bash bin/terminate_activity.sh

*/

-- Test table bloat estimation queries

WITH pgtoolkit AS (
    -- https://github.com/grayhemp/pgtoolkit
    SELECT
        nspname, relname,
        CASE WHEN size::real > 0 THEN
            round(
                100 * (
                    1 - (pure_page_count * 100 / fillfactor) / (size::real / bs)
                )::numeric, 2
            )
        ELSE 0 END AS bloat_factor
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
), ioguix AS (
    -- https://github.com/ioguix/pgsql-bloat-estimation
    /* WARNING: executed with a non-superuser role, the query inspect only tables you are granted to read.
    * This query is compatible with PostgreSQL 9.0 and more
    */
    SELECT current_database(), schemaname, tblname, bs*tblpages AS real_size,
      (tblpages-est_tblpages)*bs AS extra_size,
      CASE WHEN tblpages - est_tblpages > 0
        THEN 100 * (tblpages - est_tblpages)/tblpages::float
        ELSE 0
      END AS extra_ratio, fillfactor, (tblpages-est_tblpages_ff)*bs AS bloat_size,
      CASE WHEN tblpages - est_tblpages_ff > 0
        THEN 100 * (tblpages - est_tblpages_ff)/tblpages::float
        ELSE 0
      END AS bloat_ratio, is_na
      -- , (pst).free_percent + (pst).dead_tuple_percent AS real_frag
    FROM (
      SELECT ceil( reltuples / ( (bs-page_hdr)/tpl_size ) ) + ceil( toasttuples / 4 ) AS est_tblpages,
        ceil( reltuples / ( (bs-page_hdr)*fillfactor/(tpl_size*100) ) ) + ceil( toasttuples / 4 ) AS est_tblpages_ff,
        tblpages, fillfactor, bs, tblid, schemaname, tblname, heappages, toastpages, is_na
        -- , stattuple.pgstattuple(tblid) AS pst
      FROM (
        SELECT
          ( 4 + tpl_hdr_size + tpl_data_size + (2*ma)
            - CASE WHEN tpl_hdr_size%ma = 0 THEN ma ELSE tpl_hdr_size%ma END
            - CASE WHEN ceil(tpl_data_size)::int%ma = 0 THEN ma ELSE ceil(tpl_data_size)::int%ma END
          ) AS tpl_size, bs - page_hdr AS size_per_block, (heappages + toastpages) AS tblpages, heappages,
          toastpages, reltuples, toasttuples, bs, page_hdr, tblid, schemaname, tblname, fillfactor, is_na
        FROM (
          SELECT
            tbl.oid AS tblid, ns.nspname AS schemaname, tbl.relname AS tblname, tbl.reltuples,
            tbl.relpages AS heappages, coalesce(toast.relpages, 0) AS toastpages,
            coalesce(toast.reltuples, 0) AS toasttuples,
            coalesce(substring(
              array_to_string(tbl.reloptions, ' ')
              FROM '%fillfactor=#"__#"%' FOR '#')::smallint, 100) AS fillfactor,
            current_setting('block_size')::numeric AS bs,
            CASE WHEN version()~'mingw32' OR version()~'64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS ma,
            24 AS page_hdr,
            23 + CASE WHEN MAX(coalesce(null_frac,0)) > 0 THEN ( 7 + count(*) ) / 8 ELSE 0::int END
              + CASE WHEN tbl.relhasoids THEN 4 ELSE 0 END AS tpl_hdr_size,
            sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024) ) AS tpl_data_size,
            bool_or(att.atttypid = 'pg_catalog.name'::regtype) AS is_na
          FROM pg_attribute AS att
            JOIN pg_class AS tbl ON att.attrelid = tbl.oid
            JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
            JOIN pg_stats AS s ON s.schemaname=ns.nspname
              AND s.tablename = tbl.relname AND s.inherited=false AND s.attname=att.attname
            LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
          WHERE att.attnum > 0 AND NOT att.attisdropped
            AND tbl.relkind = 'r'
          GROUP BY 1,2,3,4,5,6,7,8,9,10, tbl.relhasoids
          ORDER BY 2,3
        ) AS s
      ) AS s2
    ) AS s3
    -- WHERE NOT is_na
    --   AND tblpages*((pst).free_percent + (pst).dead_tuple_percent)::float4/100 >= 1
), pgx_scripts AS (
    -- https://github.com/pgexperts/pgx_scripts/
    -- new table bloat query
    -- still needs work; is often off by +/- 20%
    WITH constants AS (
        -- define some constants for sizes of things
        -- for reference down the query and easy maintenance
        SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma
    ),
    no_stats AS (
        -- screen out table who have attributes
        -- which dont have stats, such as JSON
        SELECT table_schema, table_name
        FROM information_schema.columns
            LEFT OUTER JOIN pg_stats
            ON table_schema = schemaname
                AND table_name = tablename
                AND column_name = attname
        WHERE attname IS NULL
            AND table_schema NOT IN ('pg_catalog', 'information_schema')
        GROUP BY table_schema, table_name
    ),
    null_headers AS (
        -- calculate null header sizes
        -- omitting tables which dont have complete stats
        -- and attributes which aren't visible
        SELECT
            hdr+1+(sum(case when null_frac <> 0 THEN 1 else 0 END)/8) as nullhdr,
            SUM((1-null_frac)*avg_width) as datawidth,
            MAX(null_frac) as maxfracsum,
            schemaname,
            tablename,
            hdr, ma, bs
        FROM pg_stats CROSS JOIN constants
            LEFT OUTER JOIN no_stats
                ON schemaname = no_stats.table_schema
                AND tablename = no_stats.table_name
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
            AND no_stats.table_name IS NULL
            AND EXISTS ( SELECT 1
                FROM information_schema.columns
                    WHERE schemaname = columns.table_schema
                        AND tablename = columns.table_name )
        GROUP BY schemaname, tablename, hdr, ma, bs
    ),
    data_headers AS (
        -- estimate header and row size
        SELECT
            ma, bs, hdr, schemaname, tablename,
            (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
            (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
        FROM null_headers
    ),
    table_estimates AS (
        -- make estimates of how large the table should be
        -- based on row and page size
        SELECT schemaname, tablename, bs,
            reltuples, relpages * bs as table_bytes,
        CEIL((reltuples*
                (datahdr + nullhdr2 + 4 + ma -
                    (CASE WHEN datahdr%ma=0
                        THEN ma ELSE datahdr%ma END)
                    )/(bs-20))) * bs AS expected_bytes
        FROM data_headers
            JOIN pg_class ON tablename = relname
            JOIN pg_namespace ON relnamespace = pg_namespace.oid
                AND schemaname = nspname
        WHERE pg_class.relkind = 'r'
    ),
    table_estimates_plus AS (
    -- add some extra metadata to the table data
    -- and calculations to be reused
    -- including whether we cant estimate it
    -- or whether we think it might be compressed
        SELECT current_database() as databasename,
                schemaname, tablename, reltuples as est_rows,
                CASE WHEN expected_bytes > 0 AND table_bytes > 0 THEN
                    TRUE ELSE FALSE END as can_estimate,
                CASE WHEN expected_bytes > table_bytes THEN
                    TRUE ELSE FALSE END as is_compressed,
                CASE WHEN table_bytes > 0
                    THEN table_bytes::NUMERIC
                    ELSE NULL::NUMERIC END
                    AS table_bytes,
                CASE WHEN expected_bytes > 0 
                    THEN expected_bytes::NUMERIC
                    ELSE NULL::NUMERIC END
                        AS expected_bytes,
                CASE WHEN expected_bytes > 0 AND table_bytes > 0
                    AND expected_bytes <= table_bytes
                    THEN (table_bytes - expected_bytes)::NUMERIC
                    ELSE 0::NUMERIC END AS bloat_bytes
        FROM table_estimates
    ),
    bloat_data AS (
        -- do final math calculations and formatting
        select current_database() as databasename,
            schemaname, tablename, can_estimate, is_compressed,
            table_bytes, round(table_bytes/(1024^2)::NUMERIC,3) as table_mb,
            expected_bytes, round(expected_bytes/(1024^2)::NUMERIC,3) as expected_mb,
            round(bloat_bytes*100/table_bytes) as pct_bloat,
            round(bloat_bytes/(1024::NUMERIC^2),2) as mb_bloat,
            table_bytes, expected_bytes
        FROM table_estimates_plus
    )
    -- filter output for bloated tables
    SELECT databasename, schemaname, tablename,
        --can_estimate, is_compressed,
        pct_bloat, mb_bloat,
        table_mb
    FROM bloat_data
    -- this where clause defines which tables actually appear
    -- in the bloat chart
    -- example below filters for tables which are either 50%
    -- bloated and more than 20mb in size, or more than 25%
    -- bloated and more than 4GB in size
    --WHERE ( pct_bloat >= 50 AND mb_bloat >= 10 )
    --    OR ( pct_bloat >= 25 AND mb_bloat >= 1000 )
    ORDER BY pct_bloat DESC
), pgstt AS (
    SELECT
        ceil((size - free_space) * 100 / fillfactor / bs) AS effective_page_count,
        round(
            (100 * (1 - (100 - free_percent) / fillfactor))::numeric, 2
        ) AS free_percent,
        ceil(size - (size - free_space) * 100 / fillfactor) AS free_space,
        relname, nspname
    FROM (
        SELECT
            current_setting('block_size')::integer AS bs,
            pg_relation_size(c.oid) AS size,
            coalesce(
                (
                    SELECT (
                        regexp_matches(
                            c.reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),
                '100')::real AS fillfactor,
            c.relname, n.nspname, pgst.*
        FROM pg_class AS c, pg_namespace AS n, LATERAL pgstattuple(c.oid) AS pgst
        WHERE c.relkind IN ('r', 't') AND n.oid = c.relnamespace
    ) AS sq
)
SELECT
    pgtoolkit.nspname, pgtoolkit.relname,
    pgstt.free_percent AS "pgstattuple",
    pgtoolkit.bloat_factor AS pgtoolkit,
    pgstt.free_percent - pgtoolkit.bloat_factor AS pgtoolkit_dev,
    round(ioguix.bloat_ratio::numeric, 2) AS ioguix,
    pgstt.free_percent - round(ioguix.bloat_ratio::numeric, 2) AS ioguix_dev,
    pgx_scripts.pct_bloat AS pgx,
    pgstt.free_percent - pgx_scripts.pct_bloat AS pgx_dev
FROM pgtoolkit, ioguix, pgx_scripts, pgstt
WHERE
    pgtoolkit.nspname = 'public' AND
    pgtoolkit.nspname = ioguix.schemaname AND
    pgtoolkit.relname = ioguix.tblname AND
    pgtoolkit.nspname = pgx_scripts.schemaname AND
    pgtoolkit.relname = pgx_scripts.tablename AND
    pgtoolkit.nspname = pgstt.nspname AND
    pgtoolkit.relname = pgstt.relname;

--
