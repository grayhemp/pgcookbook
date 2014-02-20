#!/bin/bash

# terminate_activity.sh - activity watchdog and terminator.
#
# Constantly performs server activity checks with TERMINATE_DELAY
# seconds those checks and terminates sessions that comply to
# TERMINATE_CONDITIONS. The script was made for running as a cron job
# and exits normally if another instance is running with the same
# TERMINATE_PID_FILE. If TERMINATE_STOP_FILE exists it does not
# perform any operations.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

(
    flock -xn 543 || exit 0
    trap "rm -f $TERMINATE_PID_FILE" EXIT
    echo $(cut -d ' ' -f 4 /proc/self/stat) >$TERMINATE_PID_FILE

    sql=$(cat <<EOF
SELECT CASE WHEN version < array[9, 2] THEN 'procpid' ELSE 'pid' END
FROM (
    SELECT string_to_array(
        regexp_replace(
            version(), E'.*PostgreSQL (\\\\d+\\\\.\\\\d+).*', E'\\\\1'),
        '.')::integer[] AS version
) AS s;
EOF
)

    pid_column=$($PSQL -XAt -c "$sql" postgres 2>&1) || \
        die "Can not get PID column name: $pid_column."

    sql=$(cat <<EOF
SELECT
    pg_terminate_backend($pid_column),
    now() - xact_start AS xact_duration, *
FROM pg_stat_activity
WHERE $TERMINATE_CONDITIONS
EOF
)

    while [ ! -f $TERMINATE_STOP_FILE ]; do
        $PSQL -XAtx -F ': ' -c "$sql"
        sleep $TERMINATE_DELAY
    done

    die "Stop file exists, remove it first."
) 543>>$TERMINATE_PID_FILE
