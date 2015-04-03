#!/bin/bash

# archive_tables.sh - tables archiving script.
#
# For each database in ARCHIVE_DBNAME_LIST makes a compressed SQL dump
# of each table returned by ARCHIVE_PARTS_SQL to ARCHIVE_LOCAL_DIR,
# then moves it to ARCHIVE_ARCHIVE_DIR, cleans ARCHIVE_LOCAL_DIR,
# executes the ARCHIVE_COMMAND_BEFORE_DROP function, drops the table
# and executes the ARCHIVE_COMMAND_AFTER_DROP function. If
# ARCHIVE_LOCAL_DIR is not specified or is empty, then it archives
# tables directly to ARCHIVE_ARCHIVE_DIR. The values of database
# name, table name and archived file name are sent to the
# ARCHIVE_COMMAND_*_DROP functions as $1, $2 and $3 accordingly. To
# turn dry run mode on set ARCHIVE_DRY_RUN to 'true'.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

if [[ -z "$ARCHIVE_LOCAL_DIR" ]]; then
    ARCHIVE_LOCAL_DIR=$ARCHIVE_ARCHIVE_DIR
fi

error=$(mkdir -p $ARCHIVE_ARCHIVE_DIR 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not make an archive directory'
        ['2/archive_dir']=$ARCHIVE_ARCHIVE_DIR
        ['3m/detail']=$error))"

for dbname in $ARCHIVE_DBNAME_LIST; do
    dump_start_time=$(timer)

    part_list=$($PSQL -XAt -F '.' -c "$ARCHIVE_PARTS_SQL" $dbname 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a table list'
            ['2m/detail']=$part_list))"

    if [ -z "$part_list" ]; then
        info "$(declare -pA a=(
            ['1/message']='There is nothing to archive'
            ['2/database']=$dbname))"

        continue
    fi

    ts=$(date +%Y%m%d%H%M)

    if ! $ARCHIVE_DRY_RUN; then
        error=$(mkdir -p $ARCHIVE_LOCAL_DIR/$dbname 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not make a database directory'
                ['2/database']=$dbname
                ['3m/detail']=$error))"
    fi

    for part in $part_list; do
        file=$part.$ts.dump

        if [[ $ARCHIVE_LOCAL_DIR != $ARCHIVE_ARCHIVE_DIR ]]; then
            [[ -f $ARCHIVE_LOCAL_DIR/$dbname/$file ]] &&
                die "$(declare -pA a=(
                    ['1/message']='File already exists locally'
                    ['2/database']=$dbname
                    ['3/file']=$file))"
        fi

        [[ -f $ARCHIVE_ARCHIVE_DIR/$dbname/$file ]] &&
            die "$(declare -pA a=(
                ['1/message']='File already exists in archive'
                ['2/database']=$dbname
                ['3/file']=$file))"

        if ! $ARCHIVE_DRY_RUN; then
            error=$(
                $PGDUMP -F c -Z 2 -t $part -f $ARCHIVE_LOCAL_DIR/$dbname/$file \
                    $dbname 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not dump the table'
                    ['2/database']=$dbname
                    ['3/table']=$part
                    ['4m/detail']=$error))"

            error=$(ARCHIVE_COMMAND_BEFORE_DROP $dbname $part $file 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Before-drop command error'
                    ['2/database']=$dbname
                    ['3/table']=$part
                    ['4m/detail']=$error))"

            error=$($PSQL -c "DROP TABLE $part;" $dbname 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not drop the table'
                    ['2/database']=$dbname
                    ['3/table']=$part
                    ['4m/detail']=$error))"

            error=$(ARCHIVE_COMMAND_AFTER_DROP $dbname $part $file 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='After-drop command error'
                    ['2/database']=$dbname
                    ['3/table']=$part
                    ['4m/detail']=$error))"

            info "$(declare -pA a=(
                ['1/message']='Table has been dumped'
                ['2/database']=$dbname
                ['3/table']=$part))"
        else
            info "$(declare -pA a=(
                ['1/message']='Table can be dumped'
                ['2/database']=$dbname
                ['3/table']=$part))"
        fi
    done

    dump_time=$(( ${dump_time:-0} + $(timer $dump_start_time) ))

    if ! $ARCHIVE_DRY_RUN; then
        if [ $ARCHIVE_LOCAL_DIR != $ARCHIVE_ARCHIVE_DIR ]; then
            sync_start_time=$(timer)

            error=$(
                $RSYNC $ARCHIVE_LOCAL_DIR/$dbname $ARCHIVE_ARCHIVE_DIR 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not sync the directory to archive'
                    ['2/database']=$dbname
                    ['3m/detail']=$error))"

            error=$(rm -rf $ARCHIVE_LOCAL_DIR/$dbname 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not remove the directory locally'
                    ['2/database']=$dbname
                    ['3m/detail']=$error))"

            sync_time=$(( ${sync_time:-0} + $(timer $sync_start_time) ))

            info "$(declare -pA a=(
                ['1/message']='Directory has been moved to archive'
                ['2/database']=$dbname))"
        fi
    fi
done

info "$(declare -pA a=(
    ['1/message']='Execution time, s'
    ['2/dump']=${dump_time:-null}
    ['3/sync']=${sync_time:-null}))"
