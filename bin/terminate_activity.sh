#!/bin/bash

# terminate_activity.sh - activity watchdog and terminator.
#
# Performs server activity check and terminates sessions that comply
# to TERMINATE_CONDITIONS. The script is made to run as a cron job.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

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

message=$(
    $PSQL -XAtx -F ': ' -c "$sql" postgres 2>&1) || \
    die "Can not run the terminating SQL: $message."

message=$(echo -e "$message" | sed '${/^$/d;}')

test -z "$message" || \
    die "Activity has been terminated:\n$message"

info "No activity to terminate."
