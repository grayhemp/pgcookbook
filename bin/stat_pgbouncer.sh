#!/bin/bash

# stat_pgbouncer.sh - PgBouncer statistics collecting script.
#
# Collects a variety of PgBouncer statistics. Do not forget to specify
# an appropriate connection parameters for monitored instnces.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_PGBOUNCER_FILE

instance_dsn=$(
    echo $(test ! -z "$HOST" && echo 'host='$HOST) \
         $(test ! -z "$PORT" && echo 'port='$PORT) \
         $(test ! -z "$USER" && echo 'user='$USER))

# instance responsiveness value

(
    info "Instance responsiveness for '$instance_dsn': value "$(
        $PSQL -XAtc 'SHOW HELP' pgbouncer 1>/dev/null 2>&1 \
        && echo 't' || echo 'f')'.'
)

# client connection counts by state
# server connection counts by state
# maxwait time

(
    row_list=$($PSQL -XAt -F ' ' -c "SHOW POOLS" pgbouncer 2>&1) || \
        die "Can not get a pools data for '$instance_dsn': $row_list."

    regex='(\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)$'

    while read src; do
        [[ $src =~ $regex ]] ||
            die "Can not match the pools data for '$instance_dsn': $src"

        cl_active=$(( ${cl_active:0} + ${BASH_REMATCH[1]} ))
        cl_waiting=$(( ${cl_waiting:0} + ${BASH_REMATCH[2]} ))
        sv_active=$(( ${sv_active:0} + ${BASH_REMATCH[3]} ))
        sv_idle=$(( ${sv_idle:0} + ${BASH_REMATCH[4]} ))
        sv_used=$(( ${sv_used:0} + ${BASH_REMATCH[5]} ))
        sv_tested=$(( ${sv_tested:0} + ${BASH_REMATCH[6]} ))
        sv_login=$(( ${sv_login:0} + ${BASH_REMATCH[7]} ))
        maxwait=$(( ${maxwait:0} + ${BASH_REMATCH[8]} ))
    done <<< "$row_list"

    info "Client connection counts by stat for '$instance_dsn':" \
         "active $cl_active, waiting $cl_waiting."
    info "Server connection counts by stat for '$instance_dsn':" \
         "active $sv_active, idle $sv_idle, used $sv_used, tested $sv_tested," \
         "login $sv_login."
    info "Max waiting time for '$instance_dsn', s: value $maxwait."
)

# requests count
# received and sent bytes
# request time

(
    row_list=$($PSQL -XAt -F ' ' -c "SHOW STATS" pgbouncer 2>&1) || \
        die "Can not get a stats data for '$instance_dsn': $row_list."

    regex="(\S+) stats $instance_dsn (\S+) (\S+) (\S+) (\S+) \S+ \S+ \S+ \S+$"

    src_time=$(date +%s)
    while read src; do
        src=$src_time' '$(echo $src | sed -r "s/^\S+/stats $instance_dsn/")

        [[ $src =~ $regex ]] ||
            die "Can not match the stats data for '$instance_dsn': $src"

        src_requests=$(( ${src_requests:0} + ${BASH_REMATCH[2]} ))
        src_received=$(( ${src_received:0} + ${BASH_REMATCH[3]} ))
        src_sent=$(( ${src_sent:0} + ${BASH_REMATCH[4]} ))
        src_requests_time=$(( ${src_requests_time:0} + ${BASH_REMATCH[5]} ))
    done <<< "$row_list"

    src=$(
        echo "$src_time stats $instance_dsn $src_requests $src_received" \
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
            echo "scale=3; ($src_requests_time - $snap_requests_time) /" \
                 "($requests * 1000)" | \
            bc | awk '{printf "%.3f", $0}' || echo 'N/A')

        info "Requests count for '$instance_dsn': value $requests."
        info "Network traffic for '$instance_dsn', B/s:" \
             "received $received_s, sent $sent_s."
        info "Average request time for '$instance_dsn', ms:" \
             "value $avg_request_time."
    else
        warn "No previous stats record for '$instance_dsn'" \
             "in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_PGBOUNCER_FILE && \
        echo "$src" >> $STAT_PGBOUNCER_FILE) 2>&1) ||
        die "Can not save the stats snapshot for '$instance_dsn': $error."
)

# max database/user pool utilization

(
    result=$(
        join -t '|' -o '2.1 2.2 2.3 1.2' \
            <($PSQL -XAtc 'SHOW DATABASES' pgbouncer \
              | cut -d '|' -f 4,6 | sort) \
            <($PSQL -XAtc 'SHOW POOLS' pgbouncer \
              | cut -d '|' -f 1,2,3 | sort) 2>&1) || \
        die "Can not get a pool utilization data for '$instance_dsn': $result."

    result=$(
        echo "$result" | grep -v 'pgbouncer|pgbouncer' \
             | sed -r 's/([^|]+?\|){2}/scale=2; 100 * /' | sed 's/|/\//' | bc \
             | sort -nr | head -n 1 | awk '{printf "%.2f", $0}' )

    test -z "$result" && result='N/A'

    info "Max databse/user pool utilization for '$instance_dsn', %:" \
         "value $result."
)

# client pool utilization

(
    clients_count=$($PSQL -XAtc 'SHOW CLIENTS' pgbouncer 2>&1) || \
        die "Can not get a clients data for '$instance_dsn': $clients_count."

    clients_count=$(echo "$clients_count" | wc -l)









    max_clients_conn=$($PSQL -XAtc 'SHOW CONFIG' pgbouncer 2>&1) || \
        die "Can not get a config data for '$instance_dsn': $clients_count."

    max_clients_conn=$(
        echo "$max_clients_conn" | grep max_client_conn | cut -d '|' -f 2)

    result=$(
        echo "scale=2; 100 * $clients_count / $max_clients_conn" | bc \
        | awk '{printf "%.2f", $0}')

    info "Client pool utilization for '$instance_dsn', %:" \
         "value $result."
)
