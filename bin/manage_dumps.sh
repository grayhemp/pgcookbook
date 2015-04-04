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

dump_start_time=$(timer)

error=$(mkdir -p $DUMPS_ARCHIVE_DIR 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not make an archive directory'
        ['2m/error']=$error))"

error=$(mkdir -p $DUMPS_LOCAL_DIR/$dump_dir 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not make a dump directory locally'
        ['2/dump_dir']=$dump_dir
        ['3m/error']=$error))"

error=$($PGDUMPALL -g -f $DUMPS_LOCAL_DIR/$dump_dir/globals.sql 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not dump globals'
        ['2m/error']=$error))"

for dbname in $DUMPS_DBNAME_LIST; do
    error=$(
        $PGDUMP -f $DUMPS_LOCAL_DIR/$dump_dir/$dbname.dump.gz \
            -F c -Z 2 $dbname 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not dump the database'
            ['2/database']=$dbname
            ['3m/error']=$error))"
done

dump_time=$(timer $dump_start_time)

info "$(declare -pA a=(
    ['1/message']='Dump has been made'
    ['2/dump_dir']=$dump_dir))"

if [[ $DUMPS_ARCHIVE_DIR != $DUMPS_LOCAL_DIR ]]; then
    sync_start_time=$(timer)

    error=$($RSYNC $DUMPS_LOCAL_DIR/$dump_dir $DUMPS_ARCHIVE_DIR 2>&1) || \
        die "$(declare -pA a=(
            ['1/message']='Can not copy the dump directory to archive'
            ['2/dump_dir']=$dump_dir
            ['3m/error']=$error))"

    error=$(rm -r $DUMPS_LOCAL_DIR/$dump_dir 2>&1) || \
        die "$(declare -pA a=(
            ['1/message']='Can not remove the local dump directory'
            ['2/dump_dir']=$dump_dir
            ['3m/error']=$error))"

    sync_time=$(timer $sync_start_time)

    info "$(declare -pA a=(
        ['1/message']='Dump has been archived'
        ['2/dump_dir']=$dump_dir))"
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
    die "$(declare -pA a=(
        ['1/message']='Can not get a dump list'
        ['2m/error']=$error))"

for dir in $(ls -1 $DUMPS_ARCHIVE_DIR); do
    if ! contains "$dump_list" $dir && [[ $dir =~ ^[0-9]{8}$ ]]; then
        rotation_start_time=$(timer)

        error=$(rm -r $DUMPS_ARCHIVE_DIR/$dir 2>&1) || \
            die "$(declare -pA a=(
                ['1/message']='Can not remove the obsolete dump'
                ['2/dir']=$dir
                ['3m/error']=$error))"

        rotation_time=$(( ${rotation_time:-0} + $(timer $rotation_start_time) ))

        info "$(declare -pA a=(
            ['1/message']='Obsolete dump has been removed'
            ['2/dir']=$dir))"
    fi
done

info "$(declare -pA a=(
    ['1/message']='Execution time, s'
    ['2/dump_time']=${dump_time:-null}
    ['3/sync_time']=${sync_time:-null}
    ['4/rotation_time']=${rotation_time:-null}))"
