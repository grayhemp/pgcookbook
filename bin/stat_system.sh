#!/bin/bash

# stat_system.sh - system statistics collecting script.
#
# Collects a variety of system statistics from /proc, autodetects
# partitions and network interfaces.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_SYSTEM_FILE

# load average 1, 5, 15

(
    regex='^(\S+) (\S+) (\S+)'
    src=$(cat /proc/loadavg 2>&1) ||
        die "Can not get a load average data: $src."

    [[ $src =~ $regex ]] || die "Can not match the load average data: $src."

    _1min=${BASH_REMATCH[1]}
    _5min=${BASH_REMATCH[2]}
    _15min=${BASH_REMATCH[3]}

    info "Load average: 1min $_1min, 5min $_5min, 15min $_15min."
)

# CPU user, nice, system, idle, iowait, other

(
    regex='(\S*) *cpu +(\S+) (\S+) (\S+) (\S+) (\S+) (.+)'
    src=$(date +%s)' '$(grep -E "$regex" /proc/stat 2>&1) ||
        die "Can not get a CPU data: $src."

    [[ $src =~ $regex ]] || die "Can not match the CPU data: $src."

    src_time=${BASH_REMATCH[1]}
    src_user=${BASH_REMATCH[2]}
    src_nice=${BASH_REMATCH[3]}
    src_system=${BASH_REMATCH[4]}
    src_idle=${BASH_REMATCH[5]}
    src_iowait=${BASH_REMATCH[6]}
    src_other_list=${BASH_REMATCH[7]}

    snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

    if [[ $snap =~ $regex ]]; then
        snap_time=${BASH_REMATCH[1]}
        snap_user=${BASH_REMATCH[2]}
        snap_nice=${BASH_REMATCH[3]}
        snap_system=${BASH_REMATCH[4]}
        snap_idle=${BASH_REMATCH[5]}
        snap_iowait=${BASH_REMATCH[6]}
        snap_other_list=${BASH_REMATCH[7]}

        src_other=0
        for num in $src_other_list; do
            src_other=$(( $src_other + $num))
        done

        snap_other=0
        for num in $snap_other_list; do
            snap_other=$(( $snap_other + $num))
        done

        user_int=$(( $src_user - $snap_user ))
        nice_int=$(( $src_nice - $snap_nice ))
        system_int=$(( $src_system - $snap_system ))
        idle_int=$(( $src_idle - $snap_idle ))
        iowait_int=$(( $src_iowait - $snap_iowait ))
        other_int=$(( $src_other - $snap_other ))
        total_int=$((
            $user_int + $nice_int + $system_int + $idle_int + $iowait_int +
            $other_int
        ))

        user=$(echo "scale=1; 100 * $user_int / $total_int" | \
               bc | awk '{printf "%.1f", $0}')
        nice=$(echo "scale=1; 100 * $nice_int / $total_int" | \
               bc | awk '{printf "%.1f", $0}')
        system=$(echo "scale=1; 100 * $system_int / $total_int" | \
                 bc | awk '{printf "%.1f", $0}')
        idle=$(echo "scale=1; 100 * $idle_int / $total_int" | \
               bc | awk '{printf "%.1f", $0}')
        iowait=$(echo "scale=1; 100 * $iowait_int / $total_int" | \
                 bc | awk '{printf "%.1f", $0}')
        other=$(echo "scale=1; 100 * $other_int / $total_int" | \
                 bc | awk '{printf "%.1f", $0}')

        info "CPU usage, %: user $user, nice $nice, system $system," \
             "idle $idle, iowait $iowait, other $other."
    else
        warn "No previous CPU record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
        echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "Can not save the CPU data snapshot: $error."
)

# memory total, used, free, buffers, cached
# See http://momjian.us/main/blogs/pgblog/2012.html#May_2_2012

(
    regex='MemTotal: (\S+) kB MemFree: (\S+) kB Buffers: (\S+) kB Cached: (\S+)'
    src=$(
        echo $(grep -E '^(Mem(Total|Free)|Buffers|Cached):' /proc/meminfo) \
        2>&1) ||
        die "Can not get a memory data: $src."

    [[ $src =~ $regex ]] || die "Can not match the memory data: $src."

    total=${BASH_REMATCH[1]}
    free=${BASH_REMATCH[2]}
    buffers=${BASH_REMATCH[3]}
    cached=${BASH_REMATCH[4]}

    used=$(( ($total - $free - $buffers - $cached) ))

    info "Memory size, kB: total $total, used $used, free $free," \
         "buffers $buffers, cached $cached."
)

# swap total, used, free

(
    regex='SwapTotal: (\S+) kB SwapFree: (\S+)'
    src=$(echo $(grep -E '^Swap(Total|Free):' /proc/meminfo) 2>&1) ||
        die "Can not get a swap data: $src."

    [[ $src =~ $regex ]] || die "Can not match the swap data: $src."

    total=${BASH_REMATCH[1]}
    free=${BASH_REMATCH[2]}

    used=$(( $total - $free ))

    info "Swap size, kB: total $total, used $used, free $free."
)

# context switch count

(
    regex='(\S*) *ctxt (\S+)'
    src=$(date +%s)' '$(grep -E "$regex" /proc/stat 2>&1) ||
        die "Can not get a context switch data: $src."

    [[ $src =~ $regex ]] ||
        die "Can not match the context switch data: $src."

    src_time=${BASH_REMATCH[1]}
    src_count=${BASH_REMATCH[2]}

    snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

    if [[ $snap =~ $regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_count=${BASH_REMATCH[2]}

        count_s=$(( ($src_count - $snap_count) / ($src_time - $snap_time) ))

        info "Context switch, /s: count $count_s."
    else
        warn "No previous context switch record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
        echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "Can not save the context switch snapshot: $error."
)

# pages in, out

(
    regex='(\S*) *pgpgin (\S+) pgpgout (\S+)'
    src=$(date +%s)' '$(echo $(grep -E '^pgpg(in|out) ' /proc/vmstat) 2>&1) ||
        die "Can not get a pages data: $src."

    [[ $src =~ $regex ]] || die "Can not match the pages data: $src."

    src_time=${BASH_REMATCH[1]}
    src_in=${BASH_REMATCH[2]}
    src_out=${BASH_REMATCH[3]}

    snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

    if [[ $snap =~ $regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_in=${BASH_REMATCH[2]}
        snap_out=${BASH_REMATCH[3]}

        interval=$(( $src_time - $snap_time ))

        in_s=$(( ($src_in - $snap_in) / $interval ))
        out_s=$(( ($src_out - $snap_out) / $interval ))

        info "Pages count, /s: in $in_s, out $out_s."
    else
        warn "No previous pages record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
        echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "Can not save the paging snapshot: $error."
)

# swap pages in, out

(
    regex='(\S*) *pswpin (\S+) pswpout (\S+)'
    src=$(date +%s)' '$(echo $(grep -E '^pswp(in|out) ' /proc/vmstat) 2>&1) ||
        die "Can not get a swap pages data: $src."

    [[ $src =~ $src_regex ]] || die "Can not match the swap pages data: $src."

    src_time=${BASH_REMATCH[1]}
    src_in=${BASH_REMATCH[2]}
    src_out=${BASH_REMATCH[3]}

    snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

    if [[ $snap =~ $regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_in=${BASH_REMATCH[2]}
        snap_out=${BASH_REMATCH[3]}

        interval=$(( $src_time - $snap_time ))

        in_s=$(( ($src_in - $snap_in) / $interval ))
        out_s=$(( ($src_out - $snap_out) / $interval ))

        info "Swap pages count, /s: in $in_s, out $out_s."
    else
        warn "No previous swap pages record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
        echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "Can not save the swap pages snapshot: $error."
)

# Processing partition stats

part_list=$((ls -l /dev/disk/by-uuid/* | sed 's/.*\///' | sort) 2>&1) ||
    die "Can not get a parition list for disk data: $part_list."

for part in $part_list; do
    # disk IO count read, write
    # disk IO size read, write
    # disk IO time read, write
    # disk IO request queue time, weighted time
    # https://www.kernel.org/doc/Documentation/iostats.txt
    # https://www.kernel.org/doc/Documentation/block/stat.txt

    (
        regex="(\S*) *\S+ \S+ $part (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) \S+ (\S+) (\S+)$"
        src=$(grep -E " $part " /proc/diskstats 2>&1) ||
            die "Can not get a disk data for $part: $src."
        src=$(date +%s)' '$(echo $src | sed -r 's/\s+/ /g' | sed -r 's/^ //g')

        [[ $src =~ $regex ]] ||
            die "Can not match the disk data for $part: $src."

        src_time=${BASH_REMATCH[1]}
        src_read=${BASH_REMATCH[2]}
        src_read_merged=${BASH_REMATCH[3]}
        src_read_sectors=${BASH_REMATCH[4]}
        src_read_ms=${BASH_REMATCH[5]}
        src_write=${BASH_REMATCH[6]}
        src_write_merged=${BASH_REMATCH[7]}
        src_write_sectors=${BASH_REMATCH[8]}
        src_write_ms=${BASH_REMATCH[9]}
        src_io_ms=${BASH_REMATCH[10]}
        src_w_io_ms=${BASH_REMATCH[11]}

        snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

        if [[ $snap =~ $regex ]]; then
            snap_time=${BASH_REMATCH[1]}
            snap_read=${BASH_REMATCH[2]}
            snap_read_merged=${BASH_REMATCH[3]}
            snap_read_sectors=${BASH_REMATCH[4]}
            snap_read_ms=${BASH_REMATCH[5]}
            snap_write=${BASH_REMATCH[6]}
            snap_write_merged=${BASH_REMATCH[7]}
            snap_write_sectors=${BASH_REMATCH[8]}
            snap_write_ms=${BASH_REMATCH[9]}
            snap_io_ms=${BASH_REMATCH[10]}
            snap_w_io_ms=${BASH_REMATCH[11]}

            interval=$(( $src_time - $snap_time ))

            read_s=$(( ($src_read - $snap_read) / $interval ))
            read_merged_s=$((
                ($src_read_merged - $snap_read_merged) / $interval ))
            read_sectors_s=$((
                ($src_read_sectors - $snap_read_sectors) / $interval / 2 ))
            read_ms_s=$(( ($src_read_ms - $snap_read_ms) / $interval ))
            write_s=$(( ($src_write - $snap_write) / $interval ))
            write_merged_s=$((
                ($src_write_merged - $snap_write_merged) / $interval ))
            write_sectors_s=$((
                ($src_write_sectors - $snap_write_sectors) / $interval / 2))
            write_ms_s=$(( ($src_write_ms - $snap_write_ms) / $interval ))
            io_ms_s=$(( ($src_io_ms - $snap_io_ms) / $interval ))
            w_io_ms_s=$(( ($src_w_io_ms - $snap_w_io_ms) / $interval ))

            info "Disk IO count for $part, /s:" \
                 "read $read_s, read merged $read_merged_s," \
                 "write $write_s, write merged $write_merged_s."
            info "Disk IO size for $part, kB/s:" \
                 "read $read_sectors_s, write $write_sectors_s."
            info "Disk IO ticks for $part, ms/s:" \
                 "read $read_ms_s, write $write_ms_s."
            info "Disk IO queue for $part, ms/s:" \
                 "active $io_ms_s, weighted $w_io_ms_s."
        else
            warn "No previous disk record for $part in the snapshot file."
        fi

        error=$((
            sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
            echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
            die "Can not save the disk snapshot for $part: $error."
    )

    # disk space

    if [ -z $(grep $part /proc/swaps | cut -d ' ' -f 1) ]; then
        (
            regex="$part (\S+) (\S+) (\S+) (\S+)% (\S+)$"
            src=$(
                df 2>/dev/null | sed -r 's/\s+/ /g' | grep -E "$part " | \
                xargs -l bash -c "$( \
                    echo 'echo $(ls -l $0 | sed -r 's/.* //' 2>/dev/null ||' \
                         'echo $0) $1 $2 $3 $4 $5 $6')")

            [[ $src =~ $regex ]] ||
                die "Can not match the disk space data for $part: $src."

            src_total=${BASH_REMATCH[1]}
            src_used=${BASH_REMATCH[2]}
            src_available=${BASH_REMATCH[3]}
            src_percent=${BASH_REMATCH[4]}
            src_path=${BASH_REMATCH[5]}

            info "Disk space for $part $src_path, kB:" \
                 "total $src_total, used $src_used, available $src_available."
            info "Disk space usage for $part $src_path, %:" \
                 "percent $src_percent."
        )
    fi
done

# Processing network interface stats

iface_list=$(echo $(
    cat /proc/net/dev | sed -r 's/\s+/ /g' | sed -r 's/^ //g' | \
    grep -E ' *\S+: ' | cut -d ' ' -f 1 | sed 's/://' ) 2>&1) ||
    die "Can not get a network interface list: $iface_list."

# network bytes sent and received
# network packets sent and received
# network errors

for iface in $iface_list; do
    (
        regex="(\S*) *$iface: (\S+) (\S+) (\S+) \S+ \S+ \S+ \S+ \S+ (\S+) (\S+) (\S+)"
        src=$(grep "$iface: " /proc/net/dev 2>&1) ||
            die "Can not get a network data for $iface: $src."
        src=$(date +%s)' '$(echo $src | sed -r 's/\s+/ /g' | sed -r 's/^ //g')

        [[ $src =~ $regex ]] || die "Can not match the network data for $iface."

        src_time=${BASH_REMATCH[1]}
        src_bytes_received=${BASH_REMATCH[2]}
        src_packets_received=${BASH_REMATCH[3]}
        src_errors_received=${BASH_REMATCH[4]}
        src_bytes_sent=${BASH_REMATCH[5]}
        src_packets_sent=${BASH_REMATCH[6]}
        src_errors_sent=${BASH_REMATCH[7]}

        snap=$(grep -E "$regex" $STAT_SYSTEM_FILE)

        if [[ $snap =~ $regex ]]; then
            snap_time=${BASH_REMATCH[1]}
            snap_bytes_received=${BASH_REMATCH[2]}
            snap_packets_received=${BASH_REMATCH[3]}
            snap_errors_received=${BASH_REMATCH[4]}
            snap_bytes_sent=${BASH_REMATCH[5]}
            snap_packets_sent=${BASH_REMATCH[6]}
            snap_errors_sent=${BASH_REMATCH[7]}

            interval=$(( $src_time - $snap_time ))

            bytes_received_s=$((
                ($src_bytes_received - $snap_bytes_received) / $interval ))
            packets_received_s=$((
                ($src_packets_received - $snap_packets_received) / $interval ))
            errors_received_s=$((
                ($src_errors_received - $snap_errors_received) / $interval ))
            bytes_sent_s=$((
                ($src_bytes_sent - $snap_bytes_sent) / $interval ))
            packets_sent_s=$((
                ($src_packets_sent - $snap_packets_sent) / $interval ))
            errors_sent_s=$((
                ($src_errors_sent - $snap_errors_sent) / $interval ))

            info "Network bytes for $iface, B/s:" \
                 "received $bytes_received_s, sent $bytes_sent_s."
            info "Network packets for $iface, /s:" \
                 "received $packets_received_s, sent $packets_sent_s."
            info "Network errors for $iface, /s:" \
                 "received $errors_received_s, sent $errors_sent_s."
        else
            warn "No previous network record for $iface in the snapshot file."
        fi

        error=$((
            sed -i -r "/$regex/d" $STAT_SYSTEM_FILE && \
            echo "$src" >> $STAT_SYSTEM_FILE) 2>&1) ||
            die "Can not save the network snapshot for $iface: $error."
    )
done
