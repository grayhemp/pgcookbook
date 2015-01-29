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

sql=$(cat <<EOF
SELECT
    CASE WHEN
        string_to_array(
            regexp_replace(
                version(),
                E'.*PostgreSQL (\\\\d+\.\\\\d+).*', E'\\\\1'),
            '.'
        )::integer[] < array[9,4]
    THEN 'text' ELSE 'pg_lsn' END;
EOF
)

lsn_type=$($PSQL -XAt -c "$sql" $LAG_DBNAME 2>&1) || \
    die "Can not get an lsn type: $lsn_type."

error=$(
    $PSQL -XAt -c "CREATE EXTENSION IF NOT EXISTS dblink;" \
    $LAG_DBNAME 2>&1) || \
    die "Can not create environment: $error."

error=$($PSQL -XAt -c "SELECT txid_current();" $LAG_DBNAME 2>&1) || \
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
        in_recovery boolean, receive_location $lsn_type,
        replay_location $lsn_type, replay_timestamp timestamp with time zone
    )
)
SELECT
    coalesce(receive_lag::text, 'N/A'),
    coalesce(replay_lag::text, 'N/A'),
    coalesce((extract(epoch from replay_age) * 1000)::integer::text, 'N/A'),
    in_recovery,
    (
        NOT in_recovery OR
        receive_lag IS NULL OR receive_lag > $LAG_RECEIVE OR
        replay_lag IS NULL OR replay_lag > $LAG_REPLAY OR
        replay_age IS NULL OR replay_age > '$LAG_REPLAY_AGE'::interval
    )
FROM info;
EOF
)

src=$($PSQL -XAt -F ' ' -c "$sql" $LAG_DBNAME 2>&1) ||
    die "Can not get a lag data for $LAG_DSN: $src."

regex='(\S+) (\S+) (\S+) (\S+) (\S+)'

[[ $src =~ $regex ]] || die "Can not match the lag data for $LAG_DSN: $src."

receive_lag=${BASH_REMATCH[1]}
replay_lag=${BASH_REMATCH[2]}
replay_age=${BASH_REMATCH[3]}
in_recovery=${BASH_REMATCH[4]}

if [[ ${BASH_REMATCH[5]} == 't' ]]; then
    warn "Replication lag exceeds a threashold or replica is not in recovery" \
         "for $LAG_DSN."
    out='warn'
else
    out='info'
fi

$out "Lag for $LAG_DSN, B: receive $receive_lag, replay $replay_lag."
$out "Time lag for $LAG_DSN, ms: value $replay_age."
$out "In recovery for $LAG_DSN: value $in_recovery."
