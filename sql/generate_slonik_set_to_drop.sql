SELECT
    'set drop table (origin = @origin, id = ' || tab_id ||'); #',
    tab_nspname || '.' || tab_relname
FROM _slony.sl_table
UNION ALL
SELECT
    'set drop sequence (origin = @origin, id = ' || seq_id ||'); #',
    seq_nspname || '.' || seq_relname
FROM _slony.sl_sequence
ORDER BY 1;
