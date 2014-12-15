BEGIN;

CREATE TEMP SEQUENCE tab_seq;
SELECT setval(
    'tab_seq', (SELECT max(tab_id) FROM _slony.sl_table WHERE tab_set = 1));

CREATE TEMP SEQUENCE seq_seq;
SELECT setval(
    'seq_seq', (SELECT max(seq_id) FROM _slony.sl_sequence WHERE seq_set = 1));

SELECT
    'set add table (set id = @main, origin = @origin, id = ' ||
    nextval('tab_seq') || ', fully qualified name = ''' || fullname || '''' ||
    (CASE WHEN has_pk THEN ');' ELSE ', key = ''' || uniq_index || ''');' END)
FROM (
    SELECT
        n.nspname || '.' || c.relname AS fullname,
        EXISTS (
            SELECT 1 FROM pg_catalog.pg_index
            WHERE
                indisprimary IS true AND indisvalid IS true AND indrelid = c.oid
        ) AS has_pk,
        (
            SELECT c1.relname
            FROM pg_catalog.pg_index i
            JOIN pg_catalog.pg_class c1 ON c1.oid = i.indexrelid
            WHERE
                i.indisprimary IS false AND
                i.indisunique IS true AND
                i.indisvalid IS true AND
                i.indrelid = c.oid AND
                NOT EXISTS (
                    SELECT i_attr.attname
                    FROM pg_catalog.pg_attribute t_attr
                    JOIN pg_catalog.pg_attribute i_attr ON
                        i_attr.attname = t_attr.attname AND
                        i_attr.attrelid = i.indexrelid
                    WHERE t_attr.attrelid = c.oid AND t_attr.attnotnull <> 't'
                )
            ORDER BY c1.relname LIMIT 1
        ) AS uniq_index
        FROM pg_catalog.pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE
            c.relkind = 'r' AND
            n.nspname NOT LIKE 'pg_%' AND
            n.nspname <> '_slony' AND
            n.nspname <> 'information_schema' AND
            NOT EXISTS (
                SELECT 1 FROM _slony.sl_table
                WHERE tab_relname = c.relname AND tab_nspname = n.nspname)
        ORDER BY has_pk DESC, fullname
    ) AS t1
WHERE has_pk IS true OR uniq_index IS NOT NULL
UNION ALL
SELECT
    'set add sequence (set id = @main, origin = @origin, id = ' ||
    nextval('seq_seq') || ', fully qualified name = '''||fullname||''');'
FROM (
    SELECT n.nspname||'.'||c.relname AS fullname
    FROM pg_catalog.pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE
        c.relkind = 'S' AND
        n.nspname NOT LIKE 'pg_%' AND
        n.nspname <> '_slony' AND
        n.nspname <> 'information_schema' AND
        NOT EXISTS (
            SELECT 1 FROM _slony.sl_sequence
            WHERE seq_relname = c.relname AND seq_nspname = n.nspname)
    ORDER BY fullname
) AS t1;

END;
