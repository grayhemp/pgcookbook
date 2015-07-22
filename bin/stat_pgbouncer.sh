#!/bin/bash

# stat_pgbouncer.sh - PgBouncer statistics collecting script.
#
# Collects and prints out:
#
# - instance responsiveness
# - client connection counts by state
# - server connection counts by state
# - maxwait time
# - requests count
# - received and sent bytes
# - request time
# - max database/user pool utilization (sv_active + sv_idle)
# - per database/user pool utilization (sv_active + sv_idle)
# - client pool utilization
#
# Recommended running frequency - once per 1 minute.
#
# Do not forget to specify appropriate connection parameters for
# monitored instances.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_PGBOUNCER_FILE

dsn=$(
    echo $([ ! -z "$HOST" ] && echo "host=$HOST") \
         $([ ! -z "$PORT" ] && echo "port=$PORT"))

# instance responsiveness

(
    info "$(declare -pA a=(
        ['1/message']='Instance responsiveness'
        ['2/dsn']=$dsn
        ['3/value']=$(
            $PSQL -XAtc 'SHOW HELP' pgbouncer 1>/dev/null 2>&1 \
                && echo 'true' || echo 'false')))"
)

# client connection counts by state
# server connection counts by state
# maxwait time

(
    row_list=$($PSQL -XAt -F ' ' -c "SHOW POOLS" pgbouncer 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a pools data'
            ['2/dsn']=$dsn
            ['3m/detail']=$row_list))"

    regex='(\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)$'

    while read src; do
        [[ $src =~ $regex ]] ||
            die "$(declare -pA a=(
                ['1/message']='Can not match the pools data'
                ['2/dsn']=$dsn
                ['3m/detail']=$src))"

        cl_active=$(( ${cl_active:-0} + ${BASH_REMATCH[1]} ))
        cl_waiting=$(( ${cl_waiting:-0} + ${BASH_REMATCH[2]} ))
        sv_active=$(( ${sv_active:-0} + ${BASH_REMATCH[3]} ))
        sv_idle=$(( ${sv_idle:-0} + ${BASH_REMATCH[4]} ))
        sv_used=$(( ${sv_used:-0} + ${BASH_REMATCH[5]} ))
        sv_tested=$(( ${sv_tested:-0} + ${BASH_REMATCH[6]} ))
        sv_login=$(( ${sv_login:-0} + ${BASH_REMATCH[7]} ))
        maxwait=$(( ${maxwait:-0} + ${BASH_REMATCH[8]} ))
    done <<< "$row_list"

    info "$(declare -pA a=(
        ['1/message']='Client connection counts by stat'
        ['2/dsn']=$dsn
        ['3/active']=$cl_active
        ['4/waiting']=$cl_waiting))"

    info "$(declare -pA a=(
        ['1/message']='Server connection counts by stat'
        ['2/dsn']=$dsn
        ['3/active']=$sv_active
        ['4/idle']=$sv_idle
        ['5/used']=$sv_used
        ['6/tested']=$sv_tested
        ['7/login']=$sv_login))"

    info "$(declare -pA a=(
        ['1/message']='Max waiting time'
        ['2/dsn']=$dsn
        ['3/value']=$maxwait))"
)

# requests count
# received and sent bytes
# request time

(
    row_list=$($PSQL -XAt -F ' ' -c "SHOW STATS" pgbouncer 2>&1) || \
        die "$(declare -pA a=(
            ['1/message']='Can not get a stats data'
            ['2/dsn']=$dsn
            ['3m/detail']=$row_list))"

    regex="(\S+) stats $dsn (\S+) (\S+) (\S+) (\S+) \S+ \S+ \S+ \S+$"

    src_time=$(date +%s)
    while read src; do
        src=$src_time' '$(echo $src | sed -r "s/^\S+/stats $dsn/")

        [[ $src =~ $regex ]] ||
            die "$(declare -pA a=(
                ['1/message']='Can not match the stats data'
                ['2/dsn']=$dsn
                ['3m/detail']=$src))"

        src_requests=$(( ${src_requests:-0} + ${BASH_REMATCH[2]} ))
        src_received=$(( ${src_received:-0} + ${BASH_REMATCH[3]} ))
        src_sent=$(( ${src_sent:-0} + ${BASH_REMATCH[4]} ))
        src_requests_time=$(( ${src_requests_time:-0} + ${BASH_REMATCH[5]} ))
    done <<< "$row_list"

    src=$(
        echo "$src_time stats $dsn $src_requests $src_received" \
             "$src_sent $src_requests_time 0 0 0 0")

    snap=$(grep -E "$regex" $STAT_PGBOUNCER_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_time=${BASH_REMATCH[1]}
        snap_requests=${BASH_REMATCH[2]}
        snap_received=${BASH_REMATCH[3]}
        snap_sent=${BASH_REMATCH[4]}
        snap_requests_time=${BASH_REMATCH[5]}

        interval=$(( $src_time - $snap_time ))

        requests=$(( $src_requests - $snap_requests ))
        received_s=$(( ($src_received - $snap_received) / $interval ))
        sent_s=$(( ($src_sent - $snap_sent) / $interval ))
        avg_request_time=$(
            (( $requests > 0 )) && \
            echo $src_requests_time $snap_requests_time $requests \
                | awk '{ printf "%.3f\n", ($1 - $2) / ($3 * 1000) }' || \
                    echo 'null')

        info "$(declare -pA a=(
            ['1/message']='Requests count'
            ['2/dsn']=$dsn
            ['3/value']=$requests))"

        info "$(declare -pA a=(
            ['1/message']='Network traffic, B/s'
            ['2/dsn']=$dsn
            ['3/received']=$received_s
            ['4/sent']=$sent_s))"

        info "$(declare -pA a=(
            ['1/message']='Average request time, ms'
            ['2/dsn']=$dsn
            ['3/value']=$avg_request_time))"
    else
        warn "$(declare -pA a=(
            ['1/message']='No previous stats record in the snapshot file'
            ['2/dsn']=$dsn))"
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_PGBOUNCER_FILE && \
        echo "$src" >> $STAT_PGBOUNCER_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the stats snapshot'
            ['2/dsn']=$dsn
            ['3m/detail']=$error))"
)

# max database/user pool utilization (sv_active + sv_idle)
# per database/user pool utilization (sv_active + sv_idle)

(
    dbs_src=$($PSQL -XAtc "SHOW DATABASES" pgbouncer 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a databases utilization data'
            ['2/dsn']=$dsn
            ['3m/detail']=$dbs_src))"

    pools_src=$($PSQL -XAtc "SHOW POOLS" pgbouncer 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a pools utilization data'
            ['2/dsn']=$dsn
            ['3m/detail']=$pools_src))"

    dbs_pools_src=$(
        join -t '|' -o '2.1 2.2 2.3 2.4 1.2' \
            <(echo "$dbs_src" | cut -d '|' -f 4,6 | sort) \
            <(echo "$pools_src" | cut -d '|' -f 1,2,5,6 | sort) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a databses/pools utilization data'
            ['2/dsn']=$dsn
            ['3m/detail']=$dbs_pools_src))"

    result=$(
        echo "$dbs_pools_src" \
            | sed -r 's/([^|]+?\|){2}//' | sed 's/|/ /g' \
            | awk '{ printf "%.2f\n", 100 * ($1 + $2) / $3 }' \
            | sort -nr | head -n 1)

    result=${result:-null}

    info "$(declare -pA a=(
        ['1/message']='Max databse/user pool utilization (sv_active + sv_idle), %'
        ['2/dsn']=$dsn
        ['3/value']=$result))"

    row_list=$(
        echo "$dbs_pools_src" \
            | sed -r 's/(.+)([0-9]+)\|([0-9]+)\|([0-9]+)/\1 \2 \3 \4/' \
            | awk '{ printf $1"%.2f\n", 100 * ($2 + $3) / $4 }' \
            | sort -k 3nr -t '|' | head -n 5)

    regex='(\S+)\|(\S+)\|(\S+)$'

    while read src; do
        [[ $src =~ $regex ]] ||
            die "$(declare -pA a=(
                ['1/message']='Can not match the pool utilization data'
                ['2/dsn']=$dsn
                ['3m/detail']=$src))"

        db=${BASH_REMATCH[1]}
        user=${BASH_REMATCH[2]}
        percent=${BASH_REMATCH[3]}

        info "$(declare -pA a=(
            ['1/message']='Per databse/user pool utilization (sv_active + sv_idle), %'
            ['2/dsn']=$dsn
            ['3/db']=$db
            ['4/user']=$user
            ['5/percent']=$percent))"
    done <<< "$row_list"
)

# client pool utilization

(
    clients_count=$(($PSQL -XAtc 'SHOW CLIENTS' pgbouncer | wc -l) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a clients data'
            ['2/dsn']=$dsn
            ['3m/detail']=$clients_count))"

    max_clients_conn=$((
        $PSQL -XAtc 'SHOW CONFIG' pgbouncer \
            | grep max_client_conn | cut -d '|' -f 2) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a config data'
            ['2/dsn']=$dsn
            ['3m/detail']=$max_clients_conn))"

    result=$(
        echo $clients_count $max_clients_conn \
            | awk '{printf "%.2f\n", 100 * $1 / $2}')

    info "$(declare -pA a=(
        ['1/message']='Client pool utilization, %'
        ['2/dsn']=$dsn
        ['3/value']=$result))"
)
