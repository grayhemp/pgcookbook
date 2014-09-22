#!/bin/bash

# manage_dumps.sh - SQL dumps creation and management script.
#
# Makes compressed SQL dumps of every database in DUMPS_DBNAME_LIST
# and an SQL dump of globals to a date-named directory in
# DUMPS_LOCAL_DIR and then RSYNC this directory to DUMPS_ARCHIVE_DIR,
# removing outdated ones from DUMPS_ARCHIVE_DIR based on
# DUMPS_KEEP_DAILY_PARTS, DUMPS_KEEP_WEEKLY_PARTS and
# DUMPS_KEEP_MONTHLY_PARTS. If DUMPS_LOCAL_DIR is not specified or is
# empty then all the dumps are created directly in a date-named
# directory in DUMPS_ARCHIVE_DIR.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

if [ -z $DUMPS_LOCAL_DIR ]; then
    DUMPS_LOCAL_DIR=$DUMPS_ARCHIVE_DIR
fi

dump_dir=$(date +%Y%m%d)

error=$(mkdir -p $DUMPS_LOCAL_DIR/$dump_dir 2>&1) || \
    die "Can not make $dump_dir dumps directory: $error."

error=$($PGDUMPALL -g -f $DUMPS_LOCAL_DIR/$dump_dir/globals.sql 2>&1) || \
    die "Can not dump globals: $error."

for dbname in $DUMPS_DBNAME_LIST; do
    error=$($PGDUMP -f $DUMPS_LOCAL_DIR/$dump_dir/$dbname.dump.gz \
                     -F c -Z 2 $dbname 2>&1) || \
        die "Can not dump database $dbname: $error."
done

info "Dump $dump_dir has been made."

if [ $DUMPS_ARCHIVE_DIR != $DUMPS_LOCAL_DIR ]; then
    error=$($RSYNC $DUMPS_LOCAL_DIR/$dump_dir $DUMPS_ARCHIVE_DIR 2>&1) || \
        die "Can not copy dumps to archive: $error."
    error=$(rm -r $DUMPS_LOCAL_DIR/$dump_dir 2>&1) || \
        die "Can not clean local dumps: $error."

    info "Dump $dump_dir has been archived."
fi

sql=$(cat <<EOF
SELECT to_char(now() - days , 'YYYYMMDD')
FROM (
    SELECT (n || ' days')::interval AS days
    FROM generate_series(0, 366) AS n
) AS g
WHERE
    days < '$DUMPS_KEEP_DAILY_PARTS'::interval OR
    extract(dow from now() - days) = 1 AND
        days < '$DUMPS_KEEP_WEEKLY_PARTS'::interval OR
    extract(day from now() - days) = 1 AND
        days < '$DUMPS_KEEP_MONTHLY_PARTS'::interval;
EOF
)

dump_list=$($PSQL -XAt -c "$sql" postgres 2>&1) || \
    die "Can not get dump list: $dump_list."

for dir in $(ls -1 $DUMPS_ARCHIVE_DIR); do
    if ! contains "$dump_list" $dir && [[ $dir =~ ^[0-9]{8}$ ]]; then
        error=$(rm -r $DUMPS_ARCHIVE_DIR/$dir 2>&1) || \
            die "Can not remove obsolete dump $dir: $error."

        info "Obsolete dump $dir has been removed."
    fi
done
