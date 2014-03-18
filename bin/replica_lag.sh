#!/bin/bash

# replica_lag.sh - replication lag monitoring script.
#
# The script connects to LAG_DBNAME, creates a dblink extensions if it
# does not exist, generates a minimal WAL entry performing a kind of
# replication ping, then using dblink it gets the necessary info from
# the replica specified by LAG_DSN, and prints a lag information if
# the receive location, replay location or last replayed transaction's
# age lags behind more than LAG_RECEIVE bytes, LAG_REPLAY bytes or
# LAG_REPLAY_AGE accordingly. Note, that setting LAG_REPLAY_AGE less
# or equal than the script's call period is not recommended if your
# does not have a guarantee that there will be a write activity
# between the calls, because you might get false age based
# alerts. Compatible with PostgreSQL >=9.2.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

error=$(
    $PSQL -XAt -c "CREATE EXTENSION IF NOT EXISTS dblink;" \
    $LAG_DBNAME 2>&1) || \
    die "Can not create environment: $error."

error=$(
    $PSQL -XAt -c "SELECT txid_current();" $LAG_DBNAME 2>&1) || \
    die "Can not generale a minimal WAL record: $error."

sql=$(cat <<EOF
WITH info AS (
    SELECT
        in_recovery,
        pg_xlog_location_diff(
            pg_current_xlog_location(),
            receive_location) AS receive_lag,
        pg_xlog_location_diff(
            pg_current_xlog_location(),
            replay_location) AS replay_lag,
        now() - replay_timestamp AS replay_age
    FROM dblink(
        '$LAG_DSN',
        \$q\$ SELECT
            pg_is_in_recovery(),
            pg_last_xlog_receive_location(),
            pg_last_xlog_replay_location(),
            pg_last_xact_replay_timestamp() \$q\$
    ) AS s(
        in_recovery boolean, receive_location text, replay_location text,
        replay_timestamp timestamp with time zone
    )
), filter AS (
    SELECT * FROM info
    WHERE
        NOT in_recovery OR
        receive_lag IS NULL OR receive_lag > $LAG_RECEIVE OR
        replay_lag IS NULL OR replay_lag > $LAG_REPLAY OR
        replay_age IS NULL OR replay_age > '$LAG_REPLAY_AGE'::interval
)
SELECT
    CASE WHEN in_recovery THEN
        format(
            E'Receive lag: %s\n' ||
            E'Replay lag: %s\n' ||
            E'Replay age: %s',
            coalesce(pg_size_pretty(receive_lag), 'N/A'),
            coalesce(pg_size_pretty(replay_lag), 'N/A'),
            coalesce(replay_age::text, 'N/A'))
    ELSE 'Not in recovery' END
FROM filter;
EOF
)

$PSQL -XAt -c "$sql" $LAG_DBNAME | sed '${/^$/d;}'
