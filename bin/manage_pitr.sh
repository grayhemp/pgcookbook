#!/bin/bash

# manage_pitr.sh - a base backup and wal archiving automation.
#
# Creates an archived base backup in a current date named directory in
# PITR_ARCHIVE_DIR, removes outdated base backup directories, in
# accordance with PITR_KEEP_DAYS, from PITR_ARCHIVE_DIR, and cleans
# WAL files, that are older than the oldest kept base backup, from
# PITR_WAL_ARCHIVE_DIR. If PITR_LOCAL_DIR is specified, it creates the
# base backup in this directory first and then RSYNC it to
# PITR_ARCHIVE_DIR. If PITR_WAL is set to true it starts a process of
# streaming WAL to PITR_WAL_ARCHIVE_DIR using PGRECEIVEXLOG. The
# streaming process is made for running as a cron job and exits
# normally if another instance is running with the same
# PITR_WAL_RECEIVER_LOCK_FILE.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

if $PITR_WAL; then
    error=$(mkdir -p $PITR_WAL_ARCHIVE_DIR 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make a wal directory'
            ['2/dir']=$PITR_WAL_ARCHIVE_DIR
            ['3m/detail']=$error))"

    (
        flock -xn 544
        if [ $? != 0 ]; then
            info "$(declare -pA a=(
                ['1/message']='Exiting due to another running instance'))"

            wal_count=$(ls -1 $PITR_WAL_ARCHIVE_DIR | wc -l)
            info "$(declare -pA a=(
                ['1/message']='WAL files in archive'
                ['2/count']=$wal_count))"

            exit 0
        fi

        # Originally it is a trap for the weired issue when flock
        # refuses to work when archiving to NFS mount point and
        # there are network problems
        ps ax | grep pg_receivexlog | grep "$PITR_WAL_ARCHIVE_DIR" | \
            grep -v grep >/dev/null &&
            die "$(declare -pA a=(
                ['1/message']='Unknown problem with acquiring a lock'))"

        info "$(declare -pA a=(
            ['1/message']='Staring a WAL streaming'))"

        error=$($PGRECEIVEXLOG -n -D $PITR_WAL_ARCHIVE_DIR 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Problem with the WAL streaming'
                ['2m/detail']=$error))"
    ) 544>$PITR_WAL_RECEIVER_LOCK_FILE
else
    if [ -z "$PITR_LOCAL_DIR" ]; then
        PITR_LOCAL_DIR=$PITR_ARCHIVE_DIR
    fi

    backup_dir=$(date +%Y%m%d)

    base_backup_start_time=$(timer)

    error=$(mkdir -p $PITR_ARCHIVE_DIR 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make an archive directory'
            ['2/dir']=$PITR_ARCHIVE_DIR
            ['3m/detail']=$error))"

    error=$(mkdir -p $PITR_LOCAL_DIR/$backup_dir 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make a base backup directory locally'
            ['2/dir']=$PITR_LOCAL_DIR/$backup_dir
            ['3m/detail']=$error))"

    error=$(
        $PGBASEBACKUP -F t -Z 2 -c fast -x -D $PITR_LOCAL_DIR/$backup_dir \
        2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make a base backup'
            ['2m/detail']=$error))"

    base_backup_time=$(timer $base_backup_start_time)

    info "$(declare -pA a=(
        ['1/message']='Base backup has been made'
        ['2/dir']=$PITR_LOCAL_DIR/$backup_dir))"

    if [ $PITR_ARCHIVE_DIR != $PITR_LOCAL_DIR ]; then
        sync_start_time=$(timer)

        error=$($RSYNC $PITR_LOCAL_DIR/$backup_dir $PITR_ARCHIVE_DIR 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not copy the base backup directory to archive'
                ['2/local_dir']=$PITR_LOCAL_DIR/$backup_dir
                ['3/archive_dir']=$PITR_ARCHIVE_DIR
                ['4m/detail']=$error))"

        error=$(rm -r $PITR_LOCAL_DIR/$backup_dir 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not remove the local base backup directory'
                ['2/dir']=$PITR_LOCAL_DIR/$backup_dir
                ['3m/detail']=$error))"

        sync_time=$(timer $sync_start_time)

        info "$(declare -pA a=(
            ['1/message']='Base backup has been archived'
            ['2/backup_dir']=$PITR_ARCHIVE_DIR/$backup_dir))"
    fi

    keep_list=$( \
        (ls -1t $PITR_ARCHIVE_DIR | head -n $PITR_KEEP_BACKUPS) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a list of base backups to keep'
            ['2m/detail']=$keep_list))"

    for dir in $(ls -1 $PITR_ARCHIVE_DIR); do
        if ! contains "$keep_list" $dir; then
            base_backup_rotation_start_time=$(timer)

            error=$(rm -r $PITR_ARCHIVE_DIR/$dir 2>&1) ||
                die "$(declare -pA a=(
                    ['1/message']='Can not remove the obsolete base backup'
                    ['2/dir']=$PITR_ARCHIVE_DIR/$dir
                    ['3m/detail']=$error))"

            base_backup_rotation_time=$((
                ${base_backup_rotation_time:-0} +
                $(timer $base_backup_rotation_start_time) ))

            info "$(declare -pA a=(
                ['1/message']='Obsolete base backup has been removed'
                ['2/dir']=$PITR_ARCHIVE_DIR/$dir))"
        fi
    done

    wal_rotation_start_time=$(timer)

    oldest=$((ls -1t $PITR_ARCHIVE_DIR | tail -n 1) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not find the oldest base backup'
            ['2m/detail']=$oldest))"

    error=$(
        find $PITR_WAL_ARCHIVE_DIR -ignore_readdir_race -type f \
        ! -name *.partial ! -cnewer $PITR_ARCHIVE_DIR/$oldest -delete 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not delete old WAL files from archive'
            ['2m/detail']=$error))"

    wal_rotation_time=$(timer $wal_rotation_start_time)

    info "$(declare -pA a=(
        ['1/message']='Obsolete WAL files have been cleaned'))"

    info "$(declare -pA a=(
        ['1/message']='Execution time, s'
        ['2/base_backup']=${base_backup_time:-null}
        ['3/sync']=${sync_time:-null}
        ['4/base_backup_rotation']=${base_backup_rotation_time:-null}
        ['5/wal_rotation']=${wal_rotation_time:-null}))"
fi
