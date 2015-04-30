#!/bin/bash

# terminate_activity.sh - activity watchdog and terminator.
#
# Performs server activity check and terminates sessions that comply
# to TERMINATE_CONDITIONS. The script is made to run as a cron job.
#
# Copyright (c) 2015 Sergey Konoplev
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

pid_column=$($PSQL -XAt -c "$sql" postgres 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not get a PID column name'
        ['2m/detail']=$pid_column))"

sql=$(cat <<EOF
-- We use COPY in the query because the terminate conditions might contain
-- comments
COPY (
    SELECT
        pg_terminate_backend($pid_column)::text, now() - xact_start,
        datname, usename, application_name,
        client_addr, client_hostname, client_port,
        backend_start, xact_start, query_start, state_change,
        waiting::text, state, query
    FROM pg_stat_activity
    WHERE $TERMINATE_CONDITIONS
) TO STDOUT (NULL 'null');
EOF
)

result=$($PSQL -Xc "$sql" postgres 2>&1) ||
    die "$(declare -pA a=(
        ['1/message']='Can not perform termination'
        ['2m/detail']=$result))"

if [[ -z "$result" ]]; then
    info "$(declare -pA a=(
        ['1/message']='No activity has been terminated'))"
else
    while IFS=$'\t' read -r -a l; do
        warn "$(declare -pA a=(
            ['1/message']='Activity has been terminated'
            ['2/success']=${l[0]}
            ['3/xact_duration']=${l[1]}
            ['4/datname']=${l[2]}
            ['5/usename']=${l[3]}
            ['6/application_name']=${l[4]}
            ['7/client_addr']=${l[5]}
            ['8/client_hostname']=${l[6]}
            ['9/client_port']=${l[7]}
            ['10/backend_start']=${l[8]}
            ['11/xact_start']=${l[9]}
            ['12/query_start']=${l[10]}
            ['13/state_change']=${l[11]}
            ['14/waiting']=${l[12]}
            ['15/state']=${l[13]}
            ['16m/query']=${l[14]}))"
    done <<< "$result"
fi
