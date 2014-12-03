#!/bin/bash

# archive_tables.sh - tables archiving script.
#
# For each database in ARCHIVE_DBNAME_LIST makes a compressed SQL dump
# of each table returned by ARCHIVE_PARTS_SQL to ARCHIVE_LOCAL_DIR,
# then moves it to ARCHIVE_ARCHIVE_DIR, cleans ARCHIVE_LOCAL_DIR,
# executes the ARCHIVE_COMMAND_BEFORE_DROP function, drops the table
# and executes the ARCHIVE_COMMAND_AFTER_DROP function. If
# ARCHIVE_LOCAL_DIR is not specified or is empty, then it archives
# partitions directly to ARCHIVE_ARCHIVE_DIR. The values of database
# name, table name and archived file name are sent to the
# ARCHIVE_COMMAND_*_DROP functions as $1, $2 and $3 accordingly. To
# turn dry run mode on set ARCHIVE_DRY_RUN to 'true'.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

if [ -z "$ARCHIVE_LOCAL_DIR" ]; then
    ARCHIVE_LOCAL_DIR=$ARCHIVE_ARCHIVE_DIR
fi

error=$(mkdir -p $ARCHIVE_ARCHIVE_DIR 2>&1) ||  \
    die "Can not make archive directory $ARCHIVE_ARCHIVE_DIR: $error."

for dbname in $ARCHIVE_DBNAME_LIST; do
    part_list=$($PSQL -XAt -F '.' -c "$ARCHIVE_PARTS_SQL" $dbname 2>&1) || \
        die "Can not get a partition list: $part_list."

    if [ -z "$part_list" ]; then
        info "There is nothing to archive in the database $dbname."
        continue
    fi

    ts=$(date +%Y%m%d%H%M)

    if ! $ARCHIVE_DRY_RUN; then
        error=$(mkdir -p $ARCHIVE_LOCAL_DIR/$dbname 2>&1) || \
            die "Can not make a database directory for $dbname: $error."
    fi

    for part in $part_list; do
        file=$part.$ts.dump

        if [ $ARCHIVE_LOCAL_DIR != $ARCHIVE_ARCHIVE_DIR ]; then
            test -f $ARCHIVE_LOCAL_DIR/$dbname/$file && \
                die "File $dbname/$file already exists locally."
        fi

        test -f $ARCHIVE_ARCHIVE_DIR/$dbname/$file && \
            die "File $dbname/$file allready exists in archive."

        if ! $ARCHIVE_DRY_RUN; then
            error=$($PGDUMP -F c -Z 2 -t $part \
                        -f $ARCHIVE_LOCAL_DIR/$dbname/$file $dbname 2>&1) || \
                die "Can not dump partition $part from $dbname: $error."

            error=$(ARCHIVE_COMMAND_BEFORE_DROP $dbname $part $file 2>&1) || \
                die "Before-command error for $part from $dbname: $error."

            error=$($PSQL -c "DROP TABLE $part;" $dbname 2>&1) || \
                die "Can not drop partition $part from $dbname: $error."

            error=$(ARCHIVE_COMMAND_AFTER_DROP $dbname $part $file 2>&1) || \
                die "After-command error for $part from $dbname: $error."

            info "Partition $part from $dbname dumped in $dbname/$file."
        else
            info "Partition $part from $dbname can be dumped in $dbname/$file."
        fi
    done

    if ! $ARCHIVE_DRY_RUN; then
        if [ $ARCHIVE_LOCAL_DIR != $ARCHIVE_ARCHIVE_DIR ]; then
            error=$($RSYNC $ARCHIVE_LOCAL_DIR/$dbname \
                    $ARCHIVE_ARCHIVE_DIR 2>&1) || \
                die "Can sync directory $dbname to archive: $error."
            error=$(rm -rf $ARCHIVE_LOCAL_DIR/$dbname 2>&1) || \
                die "Can not clean directory $dbname localy: $error."

            info "Moved directory $dbname to archive."
        fi
    fi
done
