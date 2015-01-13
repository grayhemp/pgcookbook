#!/bin/bash

# stat_postgres.sh - postgres statistics collecting script.
#
# Collects a variety of postgres related statistics. Compatible with
# PostgreSQL >=9.2.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_POSTGRES_FILE

# instance responds value

info 'Instance responds: value' \
    $($PSQL -XAtc 'SELECT true' 2>/dev/null || echo 'f')'.'

# postgres processes number

info 'Processes number: value '$(ps --no-headers -C postgres | wc -l)'.'

# data size for database, filesystem except xlog, xlog

(
    db_size=$(
        $PSQL -XAtc 'SELECT sum(pg_database_size(oid)) FROM pg_database' \
        2>&1) ||
        die "Can not get a database size data: $db_size."

    data_dir=$($PSQL -XAtc 'SHOW data_directory' 2>&1) ||
        die "Can not get a data dir: $data_dir."

    fs_size=$(du -b --exclude pg_xlog -sL $data_dir 2>&1) ||
        die "Can not get a filesystem size data: $fs_size."
    fs_size=$(echo $fs_size | sed -r 's/\s+.+//')

    wal_size=$(du -b -sL $data_dir/pg_xlog 2>&1) ||
        die "Can not get an xlog size data: $wal_size."
    wal_size=$(echo $wal_size | sed -r 's/\s+.+//')

    info "Data size, B:" \
         "database $db_size, filesystem except xlog $fs_size, xlog $wal_size."
)

# activity by state number
# activity by state max age of transaction

sql=$(cat <<EOF
WITH c AS (
    SELECT array[
        'active', 'disabled', 'fastpath function call', 'idle',
        'idle in transaction', 'idle in transaction (aborted)', 'unknown'
    ] AS state_list
)
SELECT
    listed_state,
    sum((pid IS NOT NULL)::integer),
    round(max(extract(epoch from now() - xact_start)))
FROM c CROSS JOIN unnest(c.state_list) AS listed_state
LEFT JOIN pg_stat_activity AS p ON
    state = listed_state OR
    listed_state = 'unknown' AND state <> all(state_list)
GROUP BY 1 ORDER BY 1
EOF
)

(
    regex=$(
        echo 'active (\S+) (\S+) disabled (\S+) (\S+)' \
             'fastpath function call (\S+) (\S+) idle (\S+) (\S+)' \
             'idle in transaction (\S+) (\S+)' \
             'idle in transaction \(aborted\) (\S+) (\S+) unknown (\S+) (\S+)')

    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get an activity by state data: $src."

    [[ $src =~ $regex ]] ||
        die "Can not match the activity by state data: $src."

    active_number=${BASH_REMATCH[1]}
    active_max_age=${BASH_REMATCH[2]}
    disabled_number=${BASH_REMATCH[3]}
    disabled_max_age=${BASH_REMATCH[4]}
    fastpath_number=${BASH_REMATCH[5]}
    fastpath_max_age=${BASH_REMATCH[6]}
    idle_number=${BASH_REMATCH[7]}
    idle_max_age=${BASH_REMATCH[8]}
    idle_tr_number=${BASH_REMATCH[9]}
    idle_tr_max_age=${BASH_REMATCH[10]}
    idle_tr_ab_number=${BASH_REMATCH[11]}
    idle_tr_ab_max_age=${BASH_REMATCH[12]}
    unknown_number=${BASH_REMATCH[13]}
    unknown_max_age=${BASH_REMATCH[14]}

    info 'Activity by state number:' \
         "active $active_number, disabled $disabled_number," \
         "fastpath function call $fastpath_number, idle $idle_number," \
         "idle in transaction $idle_tr_number," \
         "idle in transaction (aborted) $idle_tr_ab_number," \
         "unknown $unknown_number."
    info 'Activity by state max age of transaction, s:' \
         "active $active_max_age," \
         "fastpath function call $fastpath_max_age," \
         "idle in transaction $idle_tr_max_age."
)

# lock waiting activity number
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
    regex='(\S+) (\S+) (\S+)'
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get an activity stat data: $src."

    [[ $src =~ $regex ]] ||
        die "Can not match the activity stat data: $src."

    number=${BASH_REMATCH[1]}
    min=${BASH_REMATCH[2]}
    max=${BASH_REMATCH[3]}

    info "Lock waiting activity number: value $number."
    info "Lock waiting activity age, s: min $min, max $max."
)

# deadlocks number
# block operations number for buffer cache hit, read
# buffer cache hit fraction
# temp files number
# temp data written size
# transactions number committed and rolled back
# tuple extraction number fetched and returned
# tuple operations number inserted, updated and deleted

sql=$(cat <<EOF
SELECT
    extract(epoch from now())::integer, 'database stat',
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
    regex='(\S+) database stat (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)'
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a database stat data: $src."

    [[ $src =~ $regex ]] || die "Can not match the database stat data: $src."

    src_time=${BASH_REMATCH[1]}
    src_deadlocks=${BASH_REMATCH[2]}
    src_blks_hit=${BASH_REMATCH[3]}
    src_blks_read=${BASH_REMATCH[4]}
    src_temp_files=${BASH_REMATCH[5]}
    src_temp_bytes=${BASH_REMATCH[6]}
    src_xact_commit=${BASH_REMATCH[7]}
    src_xact_rollback=${BASH_REMATCH[8]}
    src_tup_fetched=${BASH_REMATCH[9]}
    src_tup_returned=${BASH_REMATCH[10]}
    src_tup_inserted=${BASH_REMATCH[11]}
    src_tup_updated=${BASH_REMATCH[12]}
    src_tup_deleted=${BASH_REMATCH[13]}

    snap=$(grep -E "$regex" $STAT_POSTGRES_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_time=${BASH_REMATCH[1]}
        snap_deadlocks=${BASH_REMATCH[2]}
        snap_blks_hit=${BASH_REMATCH[3]}
        snap_blks_read=${BASH_REMATCH[4]}
        snap_temp_files=${BASH_REMATCH[5]}
        snap_temp_bytes=${BASH_REMATCH[6]}
        snap_xact_commit=${BASH_REMATCH[7]}
        snap_xact_rollback=${BASH_REMATCH[8]}
        snap_tup_fetched=${BASH_REMATCH[9]}
        snap_tup_returned=${BASH_REMATCH[10]}
        snap_tup_inserted=${BASH_REMATCH[11]}
        snap_tup_updated=${BASH_REMATCH[12]}
        snap_tup_deleted=${BASH_REMATCH[13]}

        interval=$(( $src_time - $snap_time ))

        deadlocks=$(( $src_deadlocks - $snap_deadlocks ))
        blks_hit=$(( $src_blks_hit - $snap_blks_hit ))
        blks_read=$(( $src_blks_read - $snap_blks_read ))
        blks_hit_s=$(( $blks_hit / $interval ))
        blks_read_s=$(( $blks_read / $interval ))
        hit_fraction=$(
            (( $blks_hit + $blks_read > 0 )) && \
            echo "scale=2; $blks_hit / ($blks_hit + $blks_read)" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')
        temp_files=$(( $src_temp_files - $snap_temp_files ))
        temp_bytes=$(( $src_temp_bytes - $snap_temp_bytes ))
        xact_commit=$(( $src_xact_commit - $snap_xact_commit ))
        xact_rollback=$(( $src_xact_rollback - $snap_xact_rollback ))
        tup_fetched=$(( $src_tup_fetched - $snap_tup_fetched ))
        tup_returned=$(( $src_tup_returned - $snap_tup_returned ))
        tup_inserted=$(( $src_tup_inserted - $snap_tup_inserted ))
        tup_updated=$(( $src_tup_updated - $snap_tup_updated ))
        tup_deleted=$(( $src_tup_deleted - $snap_tup_deleted ))

        info "Deadlocks number: value $deadlocks."
        info "Block operations number, /s:" \
             "buffer cache hit $blks_hit_s, read $blks_read_s."
        info "Buffer cache hit fraction: value $hit_fraction."
        info "Temp files number: value $temp_files."
        info "Temp data written size, B: value $temp_bytes."
        info "Transaction number: commit $xact_commit, rollback $xact_rollback."
        info "Tuple extraction number:" \
             "fetched $tup_fetched, returned $tup_returned."
        info "Tuple operations number:" \
             "inserted $tup_inserted, updated $tup_updated," \
             "deleted $tup_deleted."
    else
        warn "No previous database stat record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_POSTGRES_FILE && \
        echo "$src" >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "Can not save the database stat snapshot: $error."
)

# locks by granted number

sql=$(cat <<EOF
SELECT
    status, count(granted)
FROM pg_locks RIGHT JOIN unnest(array[true, false]) AS c(status) ON
    status = granted
GROUP BY 1 ORDER BY 1
EOF
)

(
    src=$($PSQL -XAt -R ', ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a locks data: $src."

    info "Locks by granted number: $src."
)

# prepared transaction number
# prepared transaction age min, max

sql=$(cat <<EOF
SELECT
    count(1), min(prepared), max(prepared)
FROM pg_prepared_xacts
EOF
)

(
    regex='(\S+) (\S+) (\S+)'
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a prepared transaction data: $src."

    [[ $src =~ $regex ]] ||
        die "Can not match the prepared transaction data: $src."

    number=${BASH_REMATCH[1]}
    min=${BASH_REMATCH[2]}
    max=${BASH_REMATCH[3]}

    info "Prepared transactions: number $number."
    info "Prepared transaction age, s: min $min, max $max."
)

# bgwritter checkpoint number scheduled, requested
# bgwritter checkpoint time write, sync
# bgwritter buffers written by method number checkpoint, bgwriter and backends
# bgwritter event number maxwritten stops, backend fsyncs

sql=$(cat <<EOF
SELECT
    'bgwriter stat',
    checkpoints_timed, checkpoints_req,
    checkpoint_write_time, checkpoint_sync_time,
    buffers_checkpoint, buffers_clean, buffers_backend,
    maxwritten_clean, buffers_backend_fsync
FROM pg_stat_bgwriter
EOF
)

(
    regex='bgwriter stat (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)'
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a bgwriter stat data: $src."

    [[ $src =~ $regex ]] || die "Can not match the bgwriter stat data: $src."

    src_chk_timed=${BASH_REMATCH[1]}
    src_chk_req=${BASH_REMATCH[2]}
    src_chk_w_time=${BASH_REMATCH[3]}
    src_chk_s_time=${BASH_REMATCH[4]}
    src_buf_chk=${BASH_REMATCH[5]}
    src_buf_cln=${BASH_REMATCH[6]}
    src_buf_back=${BASH_REMATCH[7]}
    src_maxw=${BASH_REMATCH[8]}
    src_back_fsync=${BASH_REMATCH[9]}

    snap=$(grep -E "$regex" $STAT_POSTGRES_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_chk_timed=${BASH_REMATCH[1]}
        snap_chk_req=${BASH_REMATCH[2]}
        snap_chk_w_time=${BASH_REMATCH[3]}
        snap_chk_s_time=${BASH_REMATCH[4]}
        snap_buf_chk=${BASH_REMATCH[5]}
        snap_buf_cln=${BASH_REMATCH[6]}
        snap_buf_back=${BASH_REMATCH[7]}
        snap_maxw=${BASH_REMATCH[8]}
        snap_back_fsync=${BASH_REMATCH[9]}

        chk_timed=$(( $src_chk_timed - $snap_chk_timed ))
        chk_req=$(( $src_chk_req - $snap_chk_req ))
        chk_w_time=$(( $src_chk_w_time - $snap_chk_w_time ))
        chk_s_time=$(( $src_chk_s_time - $snap_chk_s_time ))
        buf_chk=$(( $src_buf_chk - $snap_buf_chk ))
        buf_cln=$(( $src_buf_cln - $snap_buf_cln ))
        buf_back=$(( $src_buf_back - $snap_buf_back ))
        maxw=$(( $src_maxw - $snap_maxw ))
        back_fsync=$(( $src_back_fsync - $snap_back_fsync ))

        info "Bgwriter checkpoint number:" \
             "scheduled $chk_timed, requested $chk_req."
        info "Bgwriter checkpoint time, ms:" \
             "write $chk_w_time, sync $chk_s_time."
        info "Bgwriter buffers written by method number:" \
             "checkpoint $buf_chk, bgwriter $buf_cln, backend $buf_back."
        info "Bgwriter event number:" \
             "maxwritten stops $maxw, backend fsyncs $back_fsync."
    else
        warn "No previous bgwritter stat record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_POSTGRES_FILE && \
        echo "$src" >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "Can not save the bgwritter snapshot: $error."
)

# shared buffers distribution

sql=$(cat <<EOF
SELECT c.name, coalesce(count, 0) FROM (
    SELECT
        CASE WHEN usagecount IS NULL
             THEN 'not used' ELSE usagecount::text END ||
        CASE WHEN isdirty THEN ' dirty' ELSE '' END AS name,
        count(1)
    FROM pg_buffercache
    GROUP BY usagecount, isdirty
    ORDER BY usagecount, isdirty
) AS s
RIGHT JOIN unnest(array[
    '1', '1 dirty', '2', '2 dirty', '3', '3 dirty', '4', '4 dirty',
    '5', '5 dirty', 'not used'
]) AS c(name) USING (name)
ORDER BY 1
EOF
)

(
    extension_line=$($PSQL -XAtc '\dx pg_buffercache' 2>&1) ||
        die "Can not check pg_buffercache extension: $extension_line."

    if [[ -z "$extension_line" ]]; then
        note "Can not stat shared buffers, pg_buffercache is not installed."
    else
        src=$($PSQL -XAt -R ', ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
            die "Can not get a buffercache data data: $src."

        info "Shared buffers usage count distribution: $src."
    fi
)

# conflict with recovery number by type

sql=$(cat <<EOF
SELECT
    'database conflicts stat',
    sum(confl_tablespace), sum(confl_lock), sum(confl_snapshot),
    sum(confl_bufferpin), sum(confl_deadlock)
FROM pg_stat_database_conflicts
EOF
)

(
    regex='database conflicts stat (\S+) (\S+) (\S+) (\S+) (\S+)'
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a database conflicts stat data: $src."

    [[ $src =~ $regex ]] ||
        die "Can not match the database conflicts stat data: $src."

    src_tablespace=${BASH_REMATCH[1]}
    src_lock=${BASH_REMATCH[2]}
    src_snapshot=${BASH_REMATCH[3]}
    src_bufferpin=${BASH_REMATCH[4]}
    src_deadlock=${BASH_REMATCH[5]}

    snap=$(grep -E "$regex" $STAT_POSTGRES_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_tablespace=${BASH_REMATCH[1]}
        snap_lock=${BASH_REMATCH[2]}
        snap_snapshot=${BASH_REMATCH[3]}
        snap_bufferpin=${BASH_REMATCH[4]}
        snap_deadlock=${BASH_REMATCH[5]}

        tablespace=$(( $src_tablespace - $snap_tablespace ))
        lock=$(( $src_lock - $snap_lock ))
        snapshot=$(( $src_snapshot - $snap_snapshot ))
        bufferpin=$(( $src_bufferpin - $snap_bufferpin ))
        deadlock=$(( $src_deadlock - $snap_deadlock ))

        info "Conflict with recovery number by type:" \
             "tablespace $tablespace, lock $lock, snapshot $snapshot," \
             "bufferpin $bufferpin, deadlock $deadlock."
    else
        warn "No previous database conflicts stat record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_POSTGRES_FILE && \
        echo "$src" >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "Can not save the database conflicts stat snapshot: $error."
)

# replication connection number

sql=$(cat <<EOF
SELECT count(1) FROM pg_stat_replication
EOF
)

(
    src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" 2>&1) ||
        die "Can not get a replication stat data: $src."

    info "Replication connections: number $src."
)

# seq scan change fraction value
# hot update change fraction value
# dead and live tuple number dead, live
# dead tuple fraction value
# vacuum and analyze numbers vacuum, analyze, autovacuum, autoanalyze

sql=$(cat <<EOF
SELECT
    'all tables stat',
    sum(seq_scan), sum(idx_scan),
    sum(n_tup_hot_upd), sum(n_tup_upd),
    sum(n_dead_tup), sum(n_live_tup),
    sum(vacuum_count), sum(analyze_count),
    sum(autovacuum_count), sum(autoanalyze_count)
FROM pg_stat_all_tables
EOF
)

(
    db_list=$(
        $PSQL -XAt -c "SELECT datname FROM pg_database WHERE datallowconn"
        2>&1) ||
        die "Can not get a database list: $src."

    regex='all tables stat (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)'

    for db in $db_list; do
        src=$($PSQL -XAt -R ' ' -F ' ' -P 'null=null' -c "$sql" $db 2>&1) ||
            die "Can not get an all tables stat data: $src."

        [[ $src =~ $regex ]] ||
            die "Can not match the all tables stat data: $src."

        src_seq_scan=$(( ${src_seq_scan:0} + ${BASH_REMATCH[1]} ))
        src_idx_scan=$(( ${src_idx_scan:0} + ${BASH_REMATCH[2]} ))
        src_n_tup_hot_upd=$(( ${src_n_tup_hot_upd:0} + ${BASH_REMATCH[3]} ))
        src_n_tup_upd=$(( ${src_n_tup_upd:0} + ${BASH_REMATCH[4]} ))
        n_dead_tup=$(( ${n_dead_tup:0} + ${BASH_REMATCH[5]} ))
        n_live_tup=$(( ${n_live_tup:0} + ${BASH_REMATCH[6]} ))
        src_vacuum_count=$(( ${src_vacuum_count:0} + ${BASH_REMATCH[7]} ))
        src_analyze_count=$(( ${src_analyze_count:0} + ${BASH_REMATCH[8]} ))
        src_autovacuum_count=$((
            ${src_autovacuum_count:0} + ${BASH_REMATCH[9]} ))
        src_autoanalyze_count=$((
            ${src_autoanalyze_count:0} + ${BASH_REMATCH[10]} ))
    done

    src=$(
        echo "all tables stat $src_seq_scan $src_idx_scan $src_n_tup_hot_upd" \
             "$src_n_tup_upd $n_dead_tup $n_live_tup $src_vacuum_count" \
             "$src_analyze_count $src_autovacuum_count $src_autoanalyze_count")

    snap=$(grep -E "$regex" $STAT_POSTGRES_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_seq_scan=${BASH_REMATCH[1]}
        snap_idx_scan=${BASH_REMATCH[2]}
        snap_n_tup_hot_upd=${BASH_REMATCH[3]}
        snap_n_tup_upd=${BASH_REMATCH[4]}
        snap_vacuum_count=${BASH_REMATCH[7]}
        snap_analyze_count=${BASH_REMATCH[8]}
        snap_autovacuum_count=${BASH_REMATCH[9]}
        snap_autoanalyze_count=${BASH_REMATCH[10]}

        seq_scan=$(( $src_seq_scan - $snap_seq_scan ))
        idx_scan=$(( $src_idx_scan - $snap_idx_scan ))
        n_tup_hot_upd=$(( $src_n_tup_hot_upd - $snap_n_tup_hot_upd ))
        n_tup_upd=$(( $src_n_tup_upd - $snap_n_tup_upd ))
        vacuum_count=$(( $src_vacuum_count - $snap_vacuum_count ))
        analyze_count=$(( $src_analyze_count - $snap_analyze_count ))
        autovacuum_count=$(( $src_autovacuum_count - $snap_autovacuum_count ))
        autoanalyze_count=$((
            $src_autoanalyze_count - $snap_autoanalyze_count ))

        seq_scan_fraction=$(
            (( $seq_scan + $idx_scan > 0 )) && \
            echo "scale=2; $seq_scan / ($seq_scan + $idx_scan)" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')
        hot_update_fraction=$(
            (( $n_tup_upd > 0 )) && \
            echo "scale=2; $n_tup_hot_upd / $n_tup_upd" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')
        dead_tuple_fraction=$(
            (( $n_dead_tup + $n_live_tup > 0 )) && \
            echo "scale=2; $n_dead_tup / ($n_dead_tup + $n_live_tup)" | \
            bc | awk '{printf "%.2f", $0}' || echo 'null')

        info "Seq scan fraction: value $seq_scan_fraction."
        info "Hot update fraction: value $hot_update_fraction."
        info "Dead and live tuple numer: dead $n_dead_tup, live $n_live_tup."
        info "Dead tuple fraction: value $dead_tuple_fraction."
        info "Vacuum and analyze numbers:" \
             "vacuum $vacuum_count, analyze $analyze_count," \
             "autovacuum $autovacuum_count, autoanalyze $autoanalyze_count."
    else
        warn "No previous all tables stat record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_POSTGRES_FILE && \
        echo "$src" >> $STAT_POSTGRES_FILE) 2>&1) ||
        die "Can not save the all tables stat snapshot: $error."
)
