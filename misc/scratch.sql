-- Stat statements

DROP TABLE public._stat_statements;

DROP FUNCTION public._stat_statements_get_report(
    timestamp with time zone, timestamp with time zone, integer, integer);

DO $do$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = '_stat_statements' AND schemaname = 'public'
    ) THEN
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

        CREATE TABLE public._stat_statements AS
        SELECT NULL::timestamp with time zone AS created, *
        FROM pg_stat_statements LIMIT 0;

        CREATE INDEX _stat_statements_created
        ON public._stat_statements (created);

        CREATE OR REPLACE FUNCTION public._stat_statements_get_report(
            i_since timestamp with time zone, i_till timestamp with time zone,
            i_n integer, i_order integer, -- 0 - by time, 1 - by calls
            OUT o_report text)
        RETURNS text LANGUAGE 'plpgsql' AS $function$
        BEGIN
            WITH q1 AS (
                SELECT
                    sum(total_time) AS time,
                    sum(total_time) / sum(calls) AS time_avg,
                    sum(rows) AS rows,
                    sum(rows) / sum(calls) AS rows_avg,
                    sum(calls) AS calls,
                    string_agg(usename, ' ') AS users,
                    string_agg(datname, ' ') AS dbs,
                    query AS raw_query
                FROM public._stat_statements
                LEFT JOIN pg_user ON userid = usesysid
                LEFT JOIN pg_database ON dbid = pg_database.oid
                WHERE created > i_since AND created <= i_till
                GROUP BY query
                ORDER BY
                    (1 - i_order) * sum(total_time) DESC,
                    i_order * sum(calls) DESC
            ), q2 AS (
                SELECT
                    time, time_avg, rows, rows_avg, calls, users, dbs,
                    100 * time / sum(time) OVER () AS time_percent,
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
                    sum(time_percent)::numeric(5,2) AS time_percent,
                    (sum(time) / sum(calls))::numeric(18,3) AS time_avg,
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
                    E'pos: %s\n' ||
                    E'time: %s%%, %s ms, %s ms avg\n' ||
                    E'calls: %s%%, %s\n' ||
                    E'rows: %s, %s avg\n' ||
                    E'users: %s\ndbs: %s\n\n%s',
                    row_number, time_percent, time, time_avg, calls_percent,
                    calls, rows, rows_avg, users, dbs, query),
                E'\n\n')
            FROM q3;
            RETURN;
        END $function$;
    END IF;
END $do$;

INSERT INTO public._stat_statements
SELECT now(), * FROM pg_stat_statements;

SELECT pg_stat_statements_reset();

SELECT public._stat_statements_get_report(now()::date, now()::date + 1, 3, 0);
