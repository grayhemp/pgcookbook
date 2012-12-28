SELECT 'table' AS type, n.nspname AS schema, c.relname AS name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE
    c.relkind = 'r' AND
    n.nspname NOT LIKE 'pg_%' AND
    n.nspname <> '_slony' AND
    n.nspname <> 'information_schema' AND
    NOT EXISTS (
        SELECT 1 FROM _slony.sl_table
        WHERE tab_relname = c.relname AND tab_nspname = n.nspname)
UNION ALL
SELECT 'sequence', n.nspname, c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE
    c.relkind = 'S' AND
    n.nspname NOT LIKE 'pg_%' AND
    n.nspname <> '_slony' AND
    n.nspname <> 'information_schema' AND
    NOT EXISTS (
        SELECT 1 FROM _slony.sl_sequence
        WHERE seq_relname = c.relname AND seq_nspname = n.nspname)
ORDER BY 1, 2, 3;
