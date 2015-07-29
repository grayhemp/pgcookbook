#!/bin/bash

# stat_postgres_system.sh - PostgreSQL system statistics collection script.
#
# Collects and prints out:
#
# - postgres processes count
# - data size for filesystem except xlog, xlog
#
# Recommended running frequency - once per 1 minute.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# postgres processes count

(
    info "$(declare -pA a=(
        ['1/message']='Postgres processes count'
        ['2/value']=$(ps --no-headers -C postgres | wc -l)))"
)

# data size for filesystem except xlog, xlog

(
    data_dir=$($PSQL -XAtc 'SHOW data_directory' 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a data dir'
            ['2m/detail']=$data_dir))"

    fs_size=$((
        du -b --exclude pg_xlog -sL "$data_dir" | sed -r 's/\s+.+//') 2>&1)
    if [[ $? != 0 ]]; then
        if [[ "$fs_size" =~ ^([^$'\n']+\ No\ such\ file\ or\ directory$'\n')+[0-9]+$ ]]; then
            fs_size=$(echo "$fs_size" | tail -n 1)
        else
            die "$(declare -pA a=(
                ['1/message']='Can not get a filesystem size data'
                ['2m/detail']=$fs_size))"
        fi
    fi

    wal_size=$((
        du -b -sL "$data_dir/pg_xlog" | sed -r 's/\s+.+//') 2>&1) ||
    if [[ $? != 0 ]]; then
        if [[ "$wal_size" =~ ^([^$'\n']+\ No\ such\ file\ or\ directory$'\n')+[0-9]+$ ]]; then
            wal_size=$(echo "$wal_size" | tail -n 1)
        else
            die "$(declare -pA a=(
                ['1/message']='Can not get an xlog size data'
                ['2m/detail']=$wal_size))"
        fi
    fi

    info "$(declare -pA a=(
        ['1/message']='Filesystem data size, B'
        ['3/data_except_xlog']=$fs_size
        ['4/xlog']=$wal_size))"
)
