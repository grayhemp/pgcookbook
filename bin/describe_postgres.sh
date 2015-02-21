#!/bin/bash

# describe_postgres.sh - provides details about a postgres instance.
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
    src_list=$(echo "$src_list" | grep -E '^l' | sed -r 's/^(\S+\s+){8}//')

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

# top tables by size
# top tables by tuple count
# top tables by shared buffers utilization
# top tables by total fetched tuples
# top tables by total inserted, updated and deleted rows

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

tables_by_tupple_count=$(cat <<EOF
SELECT n.nspname, c.relname, n_live_tup + n_dead_tup
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_stat_all_tables AS s ON s.relid = c.oid
WHERE c.relkind = 'r'
ORDER BY 3 DESC
LIMIT 5;
EOF
)

tables_by_shared_buffers=$(cat <<EOF
SELECT n.nspname, c.relname, count(*)
FROM pg_buffercache AS b
JOIN pg_class AS c ON c.relfilenode = b.relfilenode
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
GROUP BY 1, 2 ORDER BY 3 DESC
LIMIT 5;
EOF
)

tables_stats=$(cat <<EOF
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
)
    SELECT array_to_string(
        array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
    FROM tables_by_total_fetched
    UNION ALL
    SELECT array_to_string(
        array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
    FROM tables_by_total_inserts
    UNION ALL
    SELECT array_to_string(
        array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
    FROM tables_by_total_updates
    UNION ALL
    SELECT array_to_string(
        array_agg(array_to_string(array[s, r, v::text], ' ')), ', ')
    FROM tables_by_total_deletes
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "Can not get a database list: $src."

    for db in $db_list; do
        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$tables_by_size_sql" 2>&1) ||
                die "Can not get a tables by size data for $db: $src."

            info "Top tables by size for $db, B: $src."
        )

        (
            src=$(
                $PSQL -XAt -F ' ' -R ', ' $db -c "$tables_by_tupple_count" \
                    2>&1) ||
                die "Can not get a tables by tupple count data for $db: $src."

            info "Top tables by tupple count for $db, B: $src."
        )

        (
            extension_line=$($PSQL -XAt  $db -c '\dx pg_buffercache' 2>&1) ||
                die "Can not check pg_buffercache extension for $db:" \
                    "$extension_line."

            if [[ -z "$extension_line" ]]; then
                note "Can not stat shared buffers for tables for $db," \
                     "pg_buffercache is not installed."
            else
                src=$(
                    $PSQL -XAt -R ', ' -F ' ' $db \
                        -c "$tables_by_shared_buffers" 2>&1) ||
                    die "Can not get a buffercache data for tables for $db:" \
                        "$src."

                info "Top tables by shared buffers utilization for $db: $src."
            fi
        )

        (
            src_list=$($PSQL -XAt $db -c "$tables_stats" 2>&1) ||
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
                *)
                    die "Wrong number of lines in the tables stats for $db."
                    ;;
                esac
                line=$(( $line + 1 ))
            done <<< "$src_list"
        )
    done
)
