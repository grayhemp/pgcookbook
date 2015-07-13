WITH i AS (
    SELECT 'read'::text AS ro_role, 'write'::text AS rw_role
)
SELECT
    format(
        'GRANT %s %s.%s TO ' || ro_role || ';',
        CASE
            WHEN c.relkind ~ '[rvmf]' THEN 'SELECT ON TABLE'
            WHEN c.relkind ~ '[S]' THEN 'SELECT ON SEQUENCE'
        END,
        quote_ident(n.nspname), quote_ident(c.relname)) AS statement
FROM pg_catalog.pg_class AS c CROSS JOIN i
JOIN pg_catalog.pg_namespace AS n ON
    n.oid = c.relnamespace AND
    n.nspname !~ '^(pg_|pgq|londiste|_slony|information_schema)'
WHERE
    c.relkind ~ '[rvmfS]' AND c.relacl IS NULL OR
    c.relkind ~ '[rvmf]' AND c.relacl::text !~ ('\m' || i.ro_role || '=r') OR
    c.relkind ~ '[S]' AND c.relacl::text !~ ('\m' || i.ro_role || '=r')
UNION ALL
SELECT
    format(
        'GRANT %s %s.%s TO ' || rw_role || ';',
        CASE
            WHEN c.relkind ~ '[rvmf]' THEN
                'SELECT, INSERT, UPDATE, DELETE ON TABLE'
            WHEN c.relkind ~ '[S]' THEN 'SELECT, USAGE ON SEQUENCE'
        END,
        quote_ident(n.nspname), quote_ident(c.relname)) AS statement
FROM pg_catalog.pg_class AS c CROSS JOIN i
JOIN pg_catalog.pg_namespace AS n ON
    n.oid = c.relnamespace AND
    n.nspname !~ '^(pg_|pgq|londiste|_slony|information_schema)'
WHERE
    c.relkind ~ '[rvmfS]' AND c.relacl IS NULL OR
    c.relkind ~ '[rvmf]' AND c.relacl::text !~ ('\m' || i.rw_role || '=arwd') OR
    c.relkind ~ '[S]' AND c.relacl::text !~ ('\m' || i.rw_role || '=rU')
ORDER BY statement;
