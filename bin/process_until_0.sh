#!/bin/bash

# process_until_0.sh - a simple DML processing script.
#
# Runs a DML from standard input in the database PROCESS_DBNAME until
# it returns a zero rows result.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/utils.sh
source $(dirname $0)/config.sh

total_processed=0
processed=1
sql=$(readall)

processing_start_time=$(timer)

while [ $processed -gt 0 ]; do
    result=$($PSQL -X -c "$sql" $PROCESS_DBNAME 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not complete processing'
            ['2/processed_count']=$total_processed
            ['3m/error']=$result))"

    processed=$(echo $result | cut -d ' ' -f 2,3 | sed 's/^.* //')
    (( total_processed+=processed ))

    progress "$(declare -pA a=(
        ['1/message']='Processed rounds'
        ['2/count']=$total_processed))"
done

echo

processing_time=$(timer $processing_start_time)

info "$(declare -pA a=(
    ['1/message']='Execution time, s'
    ['2/processing']=${processing_time:-null}))"
