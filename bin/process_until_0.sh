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

while [ $processed -gt 0 ]; do
    result=$($PSQL -X -c "$sql" $PROCESS_DBNAME 2>&1) || \
        die "Can not process: $result."

    processed=$(echo $result | cut -d ' ' -f 2)
    (( total_processed+=processed ))

    progress "Processed $total_processed rows."
done
