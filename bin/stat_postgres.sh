#!/bin/bash

# stat_postgres.sh - PostgreSQL instance statistics collection script.
#
# Collects a variety of PostgreSQL instance related
# statistics. Compatible with PostgreSQL >=9.2.
#
# Copyright (c) 2014-2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_POSTGRES_FILE

# instance responsiveness

(
    info "$(declare -pA a=(
        ['1/message']='Instance responsiveness'
        ['2/value']=$(
            $PSQL -XAtc 'SELECT true::text' 2>/dev/null || echo 'false')))"
)

# data size for databases

(
    db_size=$(
        $PSQL -XAtc 'SELECT sum(pg_database_size(oid)) FROM pg_database' \
            2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database size data'
            ['2m/detail']=$db_size))"

    info "$(declare -pA a=(
        ['1/message']='Databases size, B'
        ['2/value']=$db_size))"
)

# activity by state count
# activity by state max age of transaction

sql=$(cat <<EOF
WITH c AS (
    SELECT array[
        'active', 'disabled', 'fastpath function call', 'idle',
        'idle in transaction', 'idle in transaction (aborted)', 'unknown'
    ] AS state_list
)
SELECT row_number() OVER () + 1, * FROM (
    SELECT
        regexp_replace(listed_state, E'\\\\W+', '_', 'g'),
        sum((pid IS NOT NULL)::integer),
        round(max(extract(epoch from now() - xact_start))::numeric, 2)
    FROM c
    CROSS JOIN (SELECT unnest(state_list) AS listed_state FROM c) AS ls
    LEFT JOIN pg_stat_activity AS p ON
        state = listed_state OR
        listed_state = 'unknown' AND state <> all(state_list)
    GROUP BY 1 ORDER BY 1
) AS s
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get an activity by state data'
            ['2m/detail']=$src))"

    declare -A activity_count=(
        ['1/message']='Activity by state count')
    declare -A activity_max_age=(
        ['1/message']='Activity by state max age of transaction, s')

    while IFS=$'\t' read -r -a l; do
        activity_count["${l[0]}/${l[1]}"]="${l[2]}"
        activity_max_age["${l[0]}/${l[1]}"]="${l[3]}"
    done <<< "$src"

    info "$(declare -p activity_count)"
    info "$(declare -p activity_max_age)"

)

# lock waiting activity count
# lock waiting activity age min, max

sql=$(cat <<EOF
SELECT
    count(1),
    round(min(extract(epoch from now() - xact_start))),
    round(max(extract(epoch from now() - xact_start)))
FROM pg_stat_activity WHERE waiting
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a waiting activity data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Lock waiting activity count'
        ['2/value']=${l[0]}))"
    info "$(declare -pA a=(
        ['1/message']='Lock waiting activity age, s'
        ['2/min']=${l[1]}
        ['3/max']=${l[2]}))"
)

# deadlocks count
# block operations count for buffer cache hit, read
# buffer cache hit fraction
# temp files count
# temp data written size
# transactions count committed and rolled back
# tuple extraction count fetched and returned
# tuple operations count inserted, updated and deleted

sql=$(cat <<EOF
SELECT
    extract(epoch from now())::integer,
    sum(deadlocks),
    sum(blks_hit), sum(blks_read),
    sum(temp_files), sum(temp_bytes),
    sum(xact_commit), sum(xact_rollback),
    sum(tup_fetched), sum(tup_returned),
    sum(tup_inserted), sum(tup_updated), sum(tup_deleted)
FROM pg_stat_database
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['timestamp']="${l[0]}"
        ['deadlocks']="${l[1]}"
        ['blks_hit']="${l[2]}"
        ['blks_read']="${l[3]}"
        ['temp_files']="${l[4]}"
        ['temp_bytes']="${l[5]}"
        ['xact_commit']="${l[6]}"
        ['xact_rollback']="${l[7]}"
        ['tup_fetched']="${l[8]}"
        ['tup_returned']="${l[9]}"
        ['tup_inserted']="${l[10]}"
        ['tup_updated']="${l[11]}"
        ['tup_deleted']="${l[12]}")

    regex='declare -A database_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/database_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous database stat record in the snapshot file'))"
    else
        eval "$snap_src"

        interval=$((${stat['timestamp']} - ${snap['timestamp']}))

        deadlocks=$(( ${stat['deadlocks']} - ${snap['deadlocks']} ))
        blks_hit=$(( ${stat['blks_hit']} - ${snap['blks_hit']} ))
        blks_read=$(( ${stat['blks_read']} - ${snap['blks_read']} ))
        blks_hit_s=$(( $blks_hit / $interval ))
        blks_read_s=$(( $blks_read / $interval ))
        hit_fraction=$(
            (( $blks_hit + $blks_read > 0 )) && \
            echo "scale=2; $blks_hit / ($blks_hit + $blks_read)" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')
        temp_files=$(( ${stat['temp_files']} - ${snap['temp_files']} ))
        temp_bytes=$(( ${stat['temp_bytes']} - ${snap['temp_bytes']} ))
        xact_commit=$(( ${stat['xact_commit']} - ${snap['xact_commit']} ))
        xact_rollback=$(( ${stat['xact_rollback']} - ${snap['xact_rollback']} ))
        tup_fetched=$(( ${stat['tup_fetched']} - ${snap['tup_fetched']} ))
        tup_returned=$(( ${stat['tup_returned']} - ${snap['tup_returned']} ))
        tup_inserted=$(( ${stat['tup_inserted']} - ${snap['tup_inserted']} ))
        tup_updated=$(( ${stat['tup_updated']} - ${snap['tup_updated']} ))
        tup_deleted=$(( ${stat['tup_deleted']} - ${snap['tup_deleted']} ))

        info "$(declare -pA a=(
            ['1/message']='Deadlocks count'
            ['2/value']=$deadlocks))"

        info "$(declare -pA a=(
            ['1/message']='Block operations count, /s'
            ['2/buffer_cache_hit']=$blks_hit_s
            ['3/read']=$blks_read_s))"

        info "$(declare -pA a=(
            ['1/message']='Buffer cache hit fraction'
            ['2/value']=$hit_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Temp files count'
            ['2/value']=$temp_files))"

        info "$(declare -pA a=(
            ['1/message']='Temp data written size, B'
            ['2/value']=$temp_bytes))"

        info "$(declare -pA a=(
            ['1/message']='Transaction count'
            ['2/commit']=$xact_commit
            ['3/rollback']=$xact_rollback))"

        info "$(declare -pA a=(
            ['1/message']='Tuple extraction count'
            ['2/fetched']=$tup_fetched
            ['3/returned']=$tup_returned))"

        info "$(declare -pA a=(
            ['1/message']='Tuple operations count'
            ['2/inserted']=$tup_inserted
            ['3/updated']=$tup_updated
            ['4/deleted']=$tup_deleted))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the database stat snapshot'
            ['2m/detail']=$error))"
)

# locks by granted count

sql=$(cat <<EOF
SELECT sum((NOT granted)::integer), sum(granted::integer) FROM pg_locks
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a locks data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Locks by granted count'
        ['2/not_granted']=${l[0]}
        ['3/granted']=${l[1]}))"
)

# prepared transaction count
# prepared transaction age min, max

sql=$(cat <<EOF
SELECT count(1), min(prepared), max(prepared)
FROM pg_prepared_xacts
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a prepared transaction data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"

    info "$(declare -pA a=(
        ['1/message']='Prepared transactions count'
        ['2/value']=${l[0]}))"

    info "$(declare -pA a=(
        ['1/message']='Prepared transaction age, s'
        ['2/min']=${l[1]}
        ['3/max']=${l[2]}))"
)

# bgwritter checkpoint count scheduled, requested
# bgwritter checkpoint time write, sync
# bgwritter buffers written by method count checkpoint, bgwriter and backends
# bgwritter event count maxwritten stops, backend fsyncs

sql=$(cat <<EOF
SELECT
    checkpoints_timed, checkpoints_req,
    checkpoint_write_time, checkpoint_sync_time,
    buffers_checkpoint, buffers_clean, buffers_backend,
    maxwritten_clean, buffers_backend_fsync
FROM pg_stat_bgwriter
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a bgwriter stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['chk_timed']="${l[0]}"
        ['chk_req']="${l[1]}"
        ['chk_w_time']="${l[2]}"
        ['chk_s_time']="${l[3]}"
        ['buf_chk']="${l[4]}"
        ['buf_cln']="${l[5]}"
        ['buf_back']="${l[6]}"
        ['maxw']="${l[7]}"
        ['back_fsync']="${l[8]}")

    regex='declare -A bgwriter_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/bgwriter_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous bgwriter stat record in the snapshot file'))"
    else
        eval "$snap_src"

        chk_timed=$(( ${stat['chk_timed']} - ${snap['chk_timed']} ))
        chk_req=$(( ${stat['chk_req']} - ${snap['chk_req']} ))
        chk_w_time=$(( ${stat['chk_w_time']} - ${snap['chk_w_time']} ))
        chk_s_time=$(( ${stat['chk_s_time']} - ${snap['chk_s_time']} ))
        buf_chk=$(( ${stat['buf_chk']} - ${snap['buf_chk']} ))
        buf_cln=$(( ${stat['buf_cln']} - ${snap['buf_cln']} ))
        buf_back=$(( ${stat['buf_back']} - ${snap['buf_back']} ))
        maxw=$(( ${stat['maxw']} - ${snap['maxw']} ))
        back_fsync=$(( ${stat['back_fsync']} - ${snap['back_fsync']} ))

        info "$(declare -pA a=(
            ['1/message']='Bgwriter checkpoint count'
            ['2/scheduled']=$chk_timed
            ['3/requested']=$chk_req))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter checkpoint time, ms'
            ['2/write']=$chk_w_time
            ['3/sync']=$chk_s_time))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter buffers written by method count'
            ['2/checkpoint']=$buf_chk
            ['3/backend']=$buf_back))"

        info "$(declare -pA a=(
            ['1/message']='Bgwriter event count'
            ['2/maxwritten_stops']=$maxw
            ['3/backend_fsyncs']=$back_fsync))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the bgwriter stat snapshot'
            ['2m/detail']=$error))"
)

# conflict with recovery count by type

sql=$(cat <<EOF
SELECT
    sum(confl_tablespace), sum(confl_lock), sum(confl_snapshot),
    sum(confl_bufferpin), sum(confl_deadlock)
FROM pg_stat_database_conflicts
EOF
)

(
    src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database conflicts stat data'
            ['2m/detail']=$src))"

    IFS=$'\t' read -r -a l <<< "$src"
    declare -A stat=(
        ['tablespace']="${l[0]}"
        ['lock']="${l[1]}"
        ['snapshot']="${l[2]}"
        ['bufferpin']="${l[3]}"
        ['deadlock']="${l[4]}")

    regex='declare -A database_conflicts_stat='

    snap_src=$(
        grep "$regex" $STAT_POSTGRES_FILE \
            | sed 's/database_conflicts_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous database conflicts stat record in the snapshot file'))"
    else
        eval "$snap_src"

        tablespace=$(( ${stat['tablespace']} - ${snap['tablespace']} ))
        lock=$(( ${stat['lock']} - ${snap['lock']} ))
        snapshot=$(( ${stat['snapshot']} - ${snap['snapshot']} ))
        bufferpin=$(( ${stat['bufferpin']} - ${snap['bufferpin']} ))
        deadlock=$(( ${stat['deadlock']} - ${snap['deadlock']} ))

        info "$(declare -pA a=(
            ['1/message']='Conflict with recovery count by type'
            ['2/tablespace']=$tablespace
            ['3/lock']=$lock
            ['4/snapshot']=$snapshot
            ['5/bufferpin']=$bufferpin
            ['6/deadlock']=$deadlock))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the database conflicts stat snapshot'
            ['2m/detail']=$error))"
)

# replication connection count

sql=$(cat <<EOF
SELECT count(1) FROM pg_stat_replication
EOF
)

(
    src=$($PSQL -XAt -P 'null=null' -c "$sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a replication stat data'
            ['2m/detail']=$src))"

    info "$(declare -pA a=(
        ['1/message']='Replication connections count'
        ['2/value']=$src))"
)

# seq scan change fraction value
# hot update change fraction value
# dead and live tuple count dead, live
# dead tuple fraction value
# vacuum and analyze counts vacuum, analyze, autovacuum, autoanalyze

db_list_sql=$(cat <<EOF
SELECT datname
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(oid) DESC
EOF
)

sql=$(cat <<EOF
SELECT
    sum(seq_scan), sum(idx_scan),
    sum(n_tup_hot_upd), sum(n_tup_upd),
    sum(n_dead_tup), sum(n_live_tup),
    sum(vacuum_count), sum(analyze_count),
    sum(autovacuum_count), sum(autoanalyze_count)
FROM pg_stat_all_tables
EOF
)

(
    db_list=$($PSQL -XAt -c "$db_list_sql" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a database list'
            ['2m/detail']=$db_list))"

    declare -A stat

    for db in $db_list; do
        src=$($PSQL -Xc "\copy ($sql) to stdout (NULL 'null')" $db 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a tables stat data'
                ['2/db']=$db
                ['3m/detail']=$src))"

        IFS=$'\t' read -r -a l <<< "$src"

        stat['seq_scan']=$(( ${stat['seq_scan']:-0} + ${l[0]} ))
        stat['idx_scan']=$(( ${stat['idx_scan']:-0} + ${l[1]} ))
        stat['n_tup_hot_upd']=$(( ${stat['n_tup_hot_upd']:-0} + ${l[2]} ))
        stat['n_tup_upd']=$(( ${stat['n_tup_upd']:-0} + ${l[3]} ))
        n_dead_tup=$(( ${n_dead_tup:-0} + ${l[4]} ))
        n_live_tup=$(( ${n_live_tup:-0} + ${l[5]} ))
        stat['vacuum']=$(( ${stat['vacuum']:-0} + ${l[6]} ))
        stat['analyze']=$(( ${stat['analyze']:-0} + ${l[7]} ))
        stat['autovacuum']=$(( ${stat['autovacuum']:-0} + ${l[8]} ))
        stat['autoanalyze']=$(( ${stat['autoanalyze']:-0} + ${l[9]} ))
    done

    regex='declare -A tables_stat='

    snap_src=$(grep "$regex" $STAT_POSTGRES_FILE | sed 's/tables_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous tables stat record in the snapshot file'))"
    else
        eval "$snap_src"

        seq_scan=$(( ${stat['seq_scan']} - ${snap['seq_scan']} ))
        idx_scan=$(( ${stat['idx_scan']} - ${snap['idx_scan']} ))
        n_tup_hot_upd=$(( ${stat['n_tup_hot_upd']} - ${snap['n_tup_hot_upd']} ))
        n_tup_upd=$(( ${stat['n_tup_upd']} - ${snap['n_tup_upd']} ))
        vacuum=$(( ${stat['vacuum']} - ${snap['vacuum']} ))
        analyze=$(( ${stat['analyze']} - ${snap['analyze']} ))
        autovacuum=$(( ${stat['autovacuum']} - ${snap['autovacuum']} ))
        autoanalyze=$(( ${stat['autoanalyze']} - ${snap['autoanalyze']} ))

        seq_scan_fraction=$(
            (( $seq_scan + $idx_scan > 0 )) &&
            echo "scale=2; $seq_scan / ($seq_scan + $idx_scan)" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')
        hot_update_fraction=$(
            (( $n_tup_upd > 0 )) &&
            echo "scale=2; $n_tup_hot_upd / $n_tup_upd" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')
        dead_tuple_fraction=$(
            (( $n_dead_tup + $n_live_tup > 0 )) &&
            echo "scale=2; $n_dead_tup / ($n_dead_tup + $n_live_tup)" \
                | bc | awk '{printf "%.2f", $0}' || echo 'null')

        info "$(declare -pA a=(
            ['1/message']='Seq scan fraction'
            ['2/value']=$seq_scan_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Hot update fraction'
            ['2/value']=$hot_update_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Dead and live tuple numer'
            ['2/dead']=$n_dead_tup
            ['3/live']=$n_live_tup))"

        info "$(declare -pA a=(
            ['1/message']='Dead tuple fraction'
            ['2/value']=$dead_tuple_fraction))"

        info "$(declare -pA a=(
            ['1/message']='Vacuum and analyze counts'
            ['2/vacuum']=$vacuum
            ['3/analyze']=$analyze
            ['4/autovacuum']=$autovacuum
            ['5/autoanalyze']=$autoanalyze))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_POSTGRES_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the all tables stat snapshot'
            ['2m/detail']=$error))"
)
