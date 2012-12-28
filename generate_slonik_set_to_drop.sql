SELECT
    'set drop table (origin = @master, id = ' || tab_id ||'); #',
    tab_nspname || '.' || tab_relname
FROM _slony.sl_table
UNION ALL
SELECT
    'set drop sequence (origin = @master, id = ' || seq_id ||'); #',
    seq_nspname || '.' || seq_relname
FROM _slony.sl_sequence
ORDER BY 1;
