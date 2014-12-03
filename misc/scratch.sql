-- stat_statements.sh

DROP TABLE public._stat_statements;

DROP FUNCTION public._stat_statements_get_report(
    timestamp with time zone, timestamp with time zone, integer, integer);

DO $do$
DECLARE name text;
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

    IF 'host=host3' <> '' THEN
        CREATE EXTENSION IF NOT EXISTS dblink;
    END IF;

    IF
        (
            SELECT pg_catalog.obj_description(c.oid, 'pg_class')
            FROM pg_catalog.pg_class AS c
            JOIN pg_catalog.pg_namespace AS n ON n.oid = relnamespace
            WHERE nspname = 'public' AND relname = 'stat_statements'
        ) IS DISTINCT FROM '1'
    THEN
        DROP TABLE IF EXISTS public.stat_statements;

        CREATE TABLE public.stat_statements AS
        SELECT
            NULL::text AS replica_dsn,
            NULL::timestamp with time zone AS created,
            *
        FROM pg_stat_statements LIMIT 0;

        COMMENT ON TABLE public.stat_statements IS '1';

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
        ) IS DISTINCT FROM '1'
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
            i_since timestamp with time zone, i_till timestamp with time zone,
            i_n integer, i_order integer, -- 0 - time, 1 - calls, 2 - IO
            OUT o_report text)
        RETURNS text LANGUAGE 'plpgsql' AS $function$
        BEGIN
            WITH q1 AS (
                SELECT
                    sum(total_time) AS time,
                    sum(blk_read_time + blk_write_time) AS io_time,
                    sum(total_time) / sum(calls) AS time_avg,
                    sum(blk_read_time + blk_write_time) /
                        sum(calls) AS io_time_avg,
                    sum(rows) AS rows,
                    sum(rows) / sum(calls) AS rows_avg,
                    sum(calls) AS calls,
                    string_agg(usename, ' ') AS users,
                    string_agg(datname, ' ') AS dbs,
                    regexp_replace(
                        regexp_replace(s, '--(.*?$)', '-- [comment]', 'gm'),
                        E'\\/\\*(.*?)\\*\\/', '/* [comment] */', 'gs'
                    ) AS raw_query
                FROM public.stat_statements
                LEFT JOIN pg_catalog.pg_user ON userid = usesysid
                LEFT JOIN pg_catalog.pg_database ON dbid = pg_database.oid
                WHERE
                    replica_dsn = i_replica_dsn AND
                    created > i_since AND created <= i_till
                GROUP BY query
                ORDER BY
                    CASE
                        WHEN i_order = 0 THEN sum(total_time)
                        WHEN i_order = 1 THEN sum(calls)
                        ELSE sum(blk_read_time + blk_write_time)
                    END DESC
            ), q2 AS (
                SELECT
                    time, io_time, time_avg, io_time_avg, rows, rows_avg, calls,
                    users, dbs,
                    CASE
                        WHEN sum(time) OVER () > 0 THEN
                            100 * time / sum(time) OVER ()
                        ELSE 0 END AS time_percent,
                    CASE
                        WHEN sum(time) OVER () > 0 THEN
                            100 * io_time / sum(time) OVER ()
                        ELSE 0 END AS io_time_percent,
                    CASE
                        WHEN sum(io_time) OVER () > 0 THEN
                            100 * io_time / sum(io_time) OVER ()
                        ELSE 0 END AS io_time_perc_rel,
                    100 * calls / sum(calls) OVER () AS calls_percent,
                    CASE
                        WHEN row_number() OVER () > i_n THEN 'other'
                        ELSE raw_query END AS query,
                    CASE
                        WHEN row_number() OVER () > i_n THEN i_n + 1
                        ELSE row_number() OVER () END AS row_number
                FROM q1
            ), q3 AS (
                SELECT
                    row_number,
                    sum(time)::numeric(18,3) AS time,
                    sum(io_time)::numeric(18,3) AS io_time,
                    sum(time_percent)::numeric(5,2) AS time_percent,
                    sum(io_time_percent)::numeric(5,2) AS io_time_percent,
                    sum(io_time_perc_rel)::numeric(5,2) AS io_time_perc_rel,
                    sum(time_avg)::numeric(18,3) AS time_avg,
                    sum(io_time_avg)::numeric(18,3) AS io_time_avg,
                    sum(calls) AS calls,
                    sum(calls_percent)::numeric(5,2) AS calls_percent,
                    sum(rows) AS rows,
                    (
                        sum(rows)::numeric / sum(calls)
                    )::numeric(18,3) AS rows_avg,
                    array_to_string(
                        array(
                            SELECT DISTINCT unnest(
                                string_to_array(string_agg(users, ' '), ' '))
                        ), ', '
                    ) AS users,
                    array_to_string(
                        array(
                            SELECT DISTINCT unnest(
                                string_to_array(string_agg(dbs, ' '), ' '))
                        ), ', '
                    ) AS dbs,
                    query
                FROM q2
                GROUP by query, row_number
                ORDER BY row_number
            )
            SELECT INTO o_report string_agg(
                format(
                    E'Position: %s\n' ||
                    E'Time: %s%%, %s ms, %s ms avg\n' ||
                    E'IO time: %s%% (%s%% rel), %s ms, %s ms avg\n' ||
                    E'Calls: %s%%, %s\n' ||
                    E'Rows: %s, %s avg\n' ||
                    E'Users: %s\n'||
                    E'Databases: %s\n\n%s',
                    row_number, time_percent, time, time_avg, io_time_percent,
                    io_time_perc_rel, io_time, io_time_avg, calls_percent,
                    calls, rows, rows_avg, users, dbs, query),
                E'\n\n')
            FROM q3;

            RETURN;
        END $function$;

        FOR name IN
            SELECT p.oid::regprocedure
            FROM pg_catalog.pg_proc AS p
            LEFT JOIN pg_catalog.pg_namespace AS n ON n.oid = pronamespace
            WHERE nspname = 'public' AND proname = 'stat_statements_get_report'
        LOOP
            EXECUTE 'COMMENT ON FUNCTION ' || name || ' IS ''1''';
        END LOOP;
    END IF;
END $do$;

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
FROM (VALUES (1, 2)) AS s; -- 34
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
    '', now()::date - 1, now()::date + 1, 10, 2);

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

-- terminate_activity.sh

SELECT CASE WHEN version < array[9,2] THEN 'procpid' ELSE 'pid' END
FROM (
    SELECT string_to_array(
        regexp_replace(
            version(), E'.*PostgreSQL (\\d+\\.\\d+).*', E'\\1'),
        '.')::integer[] AS version
) AS s;

/*

(
    flock -xn 543 || exit 0
    trap "rm -f $TERMINATE_PID_FILE" EXIT
    echo $(cut -d ' ' -f 4 /proc/self/stat) >$TERMINATE_PID_FILE
    ...
)

*/

SELECT pg_catalog.obj_description('public.a'::regclass, 'pg_class');

-- process_until_0.sh

DROP TABLE IF EXISTS test_process_until_0;

CREATE TABLE test_process_until_0 (i integer);

/*

bash process_until_0.sh <<EOF
INSERT INTO test_process_until_0 SELECT g.i
FROM generate_series(0, 99) AS g(i)
LEFT JOIN test_process_until_0 AS t ON t.i = g.i
WHERE t.i IS NULL
LIMIT 10;
EOF

bash process_until_0.sh <<EOF
UPDATE test_process_until_0 SET i = i + 100
WHERE i IN (SELECT i FROM test_process_until_0 WHERE i < 100 LIMIT 10);
EOF

bash process_until_0.sh <<EOF
DELETE FROM test_process_until_0
WHERE i IN (SELECT i FROM test_process_until_0 LIMIT 10);
EOF

*/

-- replica_lag.sh

SELECT txid_current();
WITH info AS (
    SELECT
        in_recovery,
        pg_xlog_location_diff(
            pg_current_xlog_location(),
            receive_location) AS receive_lag,
        pg_xlog_location_diff(
            pg_current_xlog_location(),
            replay_location) AS replay_lag,
        now() - replay_timestamp AS replay_age
    FROM dblink(
        'host=host4',
        $q$ SELECT
            pg_is_in_recovery(),
            pg_last_xlog_receive_location(),
            pg_last_xlog_replay_location(),
            pg_last_xact_replay_timestamp() $q$
    ) AS s(
        in_recovery boolean, receive_location text, replay_location text,
        replay_timestamp timestamp with time zone
    )
), filter AS (
    SELECT * FROM info
    WHERE
        NOT in_recovery OR
        receive_lag IS NULL OR receive_lag > 32 * 1024 * 1024 OR
        replay_lag IS NULL OR replay_lag > 32 * 1024 * 1024 OR
        replay_age IS NULL OR replay_age > '5 minutes'::interval
)
SELECT
    CASE WHEN in_recovery THEN
        format(
            E'Receive lag: %s\n' ||
            E'Replay lag: %s\n' ||
            E'Replay age: %s',
            coalesce(pg_size_pretty(receive_lag), 'N/A'),
            coalesce(pg_size_pretty(replay_lag), 'N/A'),
            coalesce(replay_age::text, 'N/A'))
    ELSE 'Not in recovery' END
FROM filter;

-- archive_tables.sh

/*

rm -r /mnt/archive/parts
mkdir -p /mnt/archive/parts

*/

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

bash bin/archive_tables.sh
ls -l /mnt/archive/parts

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
git -C /mnt/archive/repo ci -m 'Initial commit.'
git -C /mnt/archive/repo push origin master
ssh-keygen -t rsa -f /tmp/_repo_id_rsa

SCHEMA_SSH_KEY='/tmp/_repo_id_rsa' bash bin/commit_schema.sh

*/

\c dbname1
--
CREATE SCHEMA schema2;

/*

bash bin/commit_schema.sh

git -C /mnt/archive/repo log -p

*/

-- manage_pitr.sh

/*

PITR_WAL=true bash bin/manage_pitr.sh
PITR_WAL=true bash bin/manage_pitr.sh # shouldn't start

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

--
