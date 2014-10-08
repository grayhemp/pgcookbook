#!/bin/bash

# restore_dump.sh - script for restoring SQL dumps.
#
# Restores RESTORE_FILE to database RESTORE_DBNAME, except some
# tables, data from other tables and a part of the data from another
# tables, obtained as a result of RESTORE_FILTER_SQL,
# RESTORE_FILTER_DATA_SQL and RESTORE_FILTER_DATA_PART_SQL
# accordingly. Tables defined with RESTORE_PRESERVE_SQL are preserved
# with the same data as it was in the RESTORE_DBNAME if one existed,
# otherwise they are not restored. RESTORE_PRESERVE_DIR is used as a
# temporary storage fro preserving tables. Uses RESTORE_THREADS
# threads to restore. If the specified database exists and
# RESTORE_DROP is true it drops the database terminating all the
# connections to this database preliminarily, otherwise it exits with
# an error.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

dbname_list=$( \
    $PSQL -XAt -c "SELECT datname FROM pg_database" postgres 2>&1) || \
    die "Can not get database list: $dbname_list."

if contains "$dbname_list" $RESTORE_DBNAME; then
    preserve_list=$( \
        $PSQL -XAt -F '.'  -c "$RESTORE_PRESERVE_SQL" $RESTORE_DBNAME 2>&1) || \
        die "Can not get preserve list: $preserve_list."

    preserve_filter_list=$( \
        $PSQL -XAt -R '|' -F ' '  -c "$RESTORE_PRESERVE_SQL" \
        $RESTORE_DBNAME 2>&1) || \
        die "Can not get preserve list: $preserve_list."

    if [ ! -z "$preserve_list" ]; then
        error=$(mkdir -p $RESTORE_PRESERVE_DIR 2>&1) || \
            die "Can not make a preserve directory for $RESTORE_DBNAME: $error."

        for preserve in $preserve_list; do
            file=$RESTORE_DBNAME-$preserve.dump

            test -f $RESTORE_PRESERVE_DIR/$file && \
                die "Preserved dump $file allready exists."

            error=$($PGDUMP -F c -Z 2 -t $preserve \
                -f $RESTORE_PRESERVE_DIR/$file $RESTORE_DBNAME 2>&1) || \
                die "Can not preserve $preserve from $RESTORE_DBNAME: $error."

            info "Table $preserve from $RESTORE_DBNAME preserved in $file."
        done
    fi
fi

if $RESTORE_DROP; then
    if contains "$dbname_list" $RESTORE_DBNAME; then
        error=$($PSQL -o /dev/null -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
             WHERE datname = '$RESTORE_DBNAME'" 2>&1) || \
            die "Can not terminate connections: $error."

        error=$($PSQL -XAtq \
            -c "DROP DATABASE \"$RESTORE_DBNAME\"" postgres 2>&1) || \
            die "Can not drop database: $error."

        dbname_list=$( \
            $PSQL -XAt -c "SELECT datname FROM pg_database" postgres 2>&1) || \
            die "Can not get database list after drop: $dbname_list."
    fi
fi

if contains "$dbname_list" $RESTORE_DBNAME; then
    die "Can not restore to existing database."
fi

error=$($PSQL -XAtq -c "CREATE DATABASE \"$RESTORE_DBNAME\"" postgres 2>&1) || \
    die "Can not create database: $error."

error=$($PGRESTORE -es -d $RESTORE_DBNAME -F c $RESTORE_FILE 2>&1) || \
    die "Can not restore schema: $error."

filter_list=$( \
    $PSQL -XAt -R '|' -F ' '  -c "$RESTORE_FILTER_SQL" \
    $RESTORE_DBNAME 2>&1) || \
    die "Can not get filter list: $filter_list."

if [ ! -z "$preserve_filter_list" ]; then
    filter_list="$filter_list|$preserve_filter_list"
fi

filter_data_list=$( \
    $PSQL -XAt -R '|' -F ' '  -c "$RESTORE_FILTER_DATA_SQL" \
    $RESTORE_DBNAME 2>&1) || \
    die "Can not get filter data list: $filter_data_list."

filter_data_part_list=$( \
    $PSQL -XAt -R '|' -F ' ' -c \
    "SELECT schemaname, tablename FROM ($RESTORE_FILTER_DATA_PART_SQL) AS s" \
    $RESTORE_DBNAME 2>&1) || \
    die "Can not get filter data part list: $filter_data_part_list."

filter_data_part_create_sql=$(cat <<EOF
SELECT
    format(
        'ALTER TABLE %I.%I DISABLE TRIGGER ALL; ' ||
        'CREATE FUNCTION _tmp_%s() RETURNS trigger LANGUAGE ''plpgsql'' ' ||
        'AS \$\$ BEGIN IF (SELECT 1 FROM (SELECT NEW.*) AS s WHERE %s) ' ||
        'THEN RETURN NULL; END IF; RETURN NEW; END \$\$; ' ||
        'CREATE TRIGGER _tmp_%s BEFORE INSERT ON %I.%I FOR EACH ROW ' ||
        'EXECUTE PROCEDURE _tmp_%s(); ' ||
        'ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER _tmp_%s;',
        schemaname, tablename, n, conditions, n, schemaname, tablename, n,
        schemaname, tablename, n)
FROM (
    SELECT row_number() OVER () AS n, *
    FROM ($RESTORE_FILTER_DATA_PART_SQL) AS s1
) AS s2
EOF
)

filter_data_part_drop_sql=$(cat <<EOF
SELECT
    format(
        'DROP FUNCTION _tmp_%s() CASCADE; ' ||
        'ALTER TABLE %I.%I ENABLE TRIGGER ALL;',
        n, schemaname, tablename)
FROM (
    SELECT row_number() OVER () AS n, *
    FROM ($RESTORE_FILTER_DATA_PART_SQL) AS s1
) AS s2
EOF
)

error=$( \
    $PGRESTORE -F c -l $RESTORE_FILE | grep -vE \
    "TABLE DATA ($filter_list|$filter_data_list|$filter_data_part_list) " \
    2>&1 | tee /tmp/restore_dump.$$ ) || \
    die "Can not make filtered dump list: $error."

error=$( \
    $PGRESTORE --disable-triggers -j $RESTORE_THREADS -ea -d $RESTORE_DBNAME \
    -F c -L /tmp/restore_dump.$$ $RESTORE_FILE 2>&1) || \
    die "Can not restore filtered dump: $error."

error=$( \
    $PGRESTORE -F c -l $RESTORE_FILE | \
    grep -E "TABLE DATA ($filter_data_part_list) " 2>&1 | \
    tee /tmp/restore_dump.$$ ) || \
    die "Can not make data part dump list: $error."

error=$(
    $PSQL -XAtq -c "$filter_data_part_create_sql" $RESTORE_DBNAME | \
    xargs -I "{}" $PSQL -XAtq -c "{}" $RESTORE_DBNAME 2>&1) || \
    die "Can not create functions and triggers: $error."

error=$( \
    $PGRESTORE -j $RESTORE_THREADS -ea -d $RESTORE_DBNAME \
    -F c -L /tmp/restore_dump.$$ $RESTORE_FILE 2>&1) || \
    die "Can not restore data part dump: $error."

error=$(rm /tmp/restore_dump.$$ 2>&1) || \
    die "Can not remove dump list: $error."

error=$(
    $PSQL -XAtq -c "$filter_data_part_drop_sql" $RESTORE_DBNAME | \
    xargs -I "{}" $PSQL -XAtq -c "{}" $RESTORE_DBNAME 2>&1) || \
    die "Can not drop functions and triggers: $error."

error=$(
    echo $filter_list | sed 's/|/\n/g' | \
    sed -r 's/(.+) (.+)/DROP TABLE \1.\2 CASCADE;/' | \
    xargs -I "{}" $PSQL -XAtq -c "{}" $RESTORE_DBNAME 2>&1) || \
    die "Can not drop tables: $error."

if [ ! -z "$preserve_list" ]; then
    for preserve in $preserve_list; do
        file=$RESTORE_DBNAME-$preserve.dump

        error=$( \
            $PGRESTORE -e -d $RESTORE_DBNAME -F c \
            $RESTORE_PRESERVE_DIR/$file 2>&1) || \
            die "Can not restore preserved $file in $RESTORE_DBNAME: $error."

        info "Restored preserved $file in $RESTORE_DBNAME."

        error=$(rm $RESTORE_PRESERVE_DIR/$file 2>&1) || \
            die "Can not remove preserved dump $file: $error."

        info "Preserve dump $file removed."
    done
fi

info "Database restored."
