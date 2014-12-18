#!/bin/bash

# measure_system.sh - system statistics snapshoting script.
#
# Snapshots a variety of system statistics, like LA, CPU, memory, IO
# and network using /proc. It autodetects partitions and network
# interfaces.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $MEASURE_SYSTEM_SNAP_FILE

# load average 1, 5, 15

src_regex='^(\S+) (\S+) (\S+)'
src=$(cat /proc/loadavg 2>&1) || die "Can not get a load average data: $src."

if [[ $src =~ $src_regex ]]; then
    src_1min=${BASH_REMATCH[1]}
    src_5min=${BASH_REMATCH[2]}
    src_15min=${BASH_REMATCH[3]}

    info "Load average: $src_1min 1min, $src_5min 5min, $src_15min 15min."
else
    die "Can not match the load average data."
fi

# CPU user, nice, system, idle, iowait, other

src_regex='cpu  (\S+) (\S+) (\S+) (\S+) (\S+) (.+)'
src=$(grep -E "$src_regex" /proc/stat 2>&1) ||
    die "Can not get a CPU data: $src."
src_time=$(date +%s)

if [[ $src =~ $src_regex ]]; then
    src_user=${BASH_REMATCH[1]}
    src_nice=${BASH_REMATCH[2]}
    src_system=${BASH_REMATCH[3]}
    src_idle=${BASH_REMATCH[4]}
    src_iowait=${BASH_REMATCH[5]}
    src_other_list=${BASH_REMATCH[6]}

    snap_regex="(\S+) $src_regex"
    snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

    if [[ $snap =~ $snap_regex ]]
    then
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

        info "CPU, usage %: $user user, $nice nice, $system system," \
             "$idle idle, $iowait iowait, $other other."
    else
        warn "No previous CPU record in the snapshot file."
    fi

    error=$((
        sed -i -r "/$snap_regex/d" $MEASURE_SYSTEM_SNAP_FILE && \
        echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
        die "Can not save the CPU data snapshot: $error."
else
    die "Can not match the CPU data."
fi

# memory total, used, free, buffers, cached
# See http://momjian.us/main/blogs/pgblog/2012.html#May_2_2012

src_regex='MemTotal: (\S+) kB MemFree: (\S+) kB Buffers: (\S+) kB Cached: (\S+)'
src=$(
    echo $(grep -E '^(Mem(Total|Free)|Buffers|Cached):' /proc/meminfo) 2>&1) ||
    die "Can not get a memory data: $src."

if [[ $src =~ $src_regex ]]; then
    src_total=${BASH_REMATCH[1]}
    src_free=${BASH_REMATCH[2]}
    src_buffers=${BASH_REMATCH[3]}
    src_cached=${BASH_REMATCH[4]}

    total=$(( $src_total ))
    free=$(( $src_free ))
    used=$(( ($src_total - $src_free - $src_buffers - $src_cached) ))
    buffers=$(( $src_buffers ))
    cached=$(( $src_cached ))

    info "Memory, kB: $total total, $used used, $free free," \
         "$buffers buffers, $cached cached."
else
    die "Can not match the memory data."
fi

# swap total, used, free

src_regex='SwapTotal: (\S+) kB SwapFree: (\S+)'
src=$(echo $(grep -E '^Swap(Total|Free):' /proc/meminfo) 2>&1) ||
    die "Can not get a swap data: $src."

if [[ $src =~ $src_regex ]]; then
    src_total=${BASH_REMATCH[1]}
    src_free=${BASH_REMATCH[2]}

    total=$(( $src_total ))
    free=$(( $src_free ))
    used=$(( $src_total - $src_free ))

    info "Swap, kB: $total total, $used used, $free free."
else
    die "Can not match the swap data."
fi

# context switch count

src_regex='ctxt (\S+)'
src=$(grep -E "$src_regex" /proc/stat 2>&1) ||
    die "Can not get a context switch data: $src."
src_time=$(date +%s)

if [[ $src =~ $src_regex ]]; then
    src_count=${BASH_REMATCH[1]}

    snap_regex="(\S+) $src_regex"
    snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

    if [[ $snap =~ $snap_regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_count=${BASH_REMATCH[2]}

        count_s=$(( ($src_count - $snap_count) / ($src_time - $snap_time) ))

        info "Context switch, /s: $count_s."
    else
        warn "No previous context switch record in the snapshot file."
    fi

    error=$((
        sed -i -r "/${snap_regex}/d" $MEASURE_SYSTEM_SNAP_FILE && \
        echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
        die "Can not save the context switch snapshot: $error."
else
    die "Can not match the context switch data."
fi

# pages in, out

src_regex='pgpgin (\S+) pgpgout (\S+)'
src=$(echo $(grep -E '^pgpg(in|out) ' /proc/vmstat) 2>&1) ||
    die "Can not get a pages data: $src."
src_time=$(date +%s)

if [[ $src =~ $src_regex ]]; then
    src_in=${BASH_REMATCH[1]}
    src_out=${BASH_REMATCH[2]}

    snap_regex="(\S+) $src_regex"
    snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

    if [[ $snap =~ $snap_regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_in=${BASH_REMATCH[2]}
        snap_out=${BASH_REMATCH[3]}

        interval=$(( $src_time - $snap_time ))

        in_s=$(( ($src_in - $snap_in) / $interval ))
        out_s=$(( ($src_out - $snap_out) / $interval ))

        info "Pages, /s: $in_s in, $out_s out."
    else
        warn "No previous pages record in the snapshot file."
    fi

    error=$((
        sed -i -r "/${snap_regex}/d" $MEASURE_SYSTEM_SNAP_FILE && \
        echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
        die "Can not save the paging snapshot: $error."
else
    die "Can not match the pages data."
fi

# swap pages in, out

src_regex='pswpin (\S+) pswpout (\S+)'
src=$(echo $(grep -E '^pswp(in|out) ' /proc/vmstat) 2>&1) ||
    die "Can not get a swap pages data: $src."
src_time=$(date +%s)

if [[ $src =~ $src_regex ]]; then
    src_in=${BASH_REMATCH[1]}
    src_out=${BASH_REMATCH[2]}

    snap_regex="(\S+) $src_regex"
    snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

    if [[ $snap =~ $snap_regex ]]
    then
        snap_time=${BASH_REMATCH[1]}
        snap_in=${BASH_REMATCH[2]}
        snap_out=${BASH_REMATCH[3]}

        interval=$(( $src_time - $snap_time ))

        in_s=$(( ($src_in - $snap_in) / $interval ))
        out_s=$(( ($src_out - $snap_out) / $interval ))

        info "Swap pages, /s: $in_s in, $out_s out."
    else
        warn "No previous swap pages record in the snapshot file."
    fi

    error=$((
        sed -i -r "/${snap_regex}/d" $MEASURE_SYSTEM_SNAP_FILE && \
        echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
        die "Can not save the swap pages snapshot: $error."
else
    die "Can not match the swap pages data."
fi

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

    src_regex=" *\S+ \S+ $part (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) \S+ (\S+) (\S+)$"
    src=$((
        grep -E " $part " /proc/diskstats | sed -r 's/\s+/ /g' | \
        sed -r 's/^ //g') 2>&1) ||
        die "Can not get a disk data for $part: $src."
    src_time=$(date +%s)

    if [[ $src =~ $src_regex ]]; then
        src_read=${BASH_REMATCH[1]}
        src_read_merged=${BASH_REMATCH[2]}
        src_read_sectors=${BASH_REMATCH[3]}
        src_read_ms=${BASH_REMATCH[4]}
        src_write=${BASH_REMATCH[5]}
        src_write_merged=${BASH_REMATCH[6]}
        src_write_sectors=${BASH_REMATCH[7]}
        src_write_ms=${BASH_REMATCH[8]}
        src_io_ms=${BASH_REMATCH[9]}
        src_w_io_ms=${BASH_REMATCH[10]}

        snap_regex="(\S+) $src_regex"
        snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

        if [[ $snap =~ $snap_regex ]]
        then
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
                 "$read_s read, $read_merged_s read merged," \
                 "$write_s write, $write_merged_s write merged."
            info "Disk IO size for $part, kB/s:" \
                 "$read_sectors_s read, $write_sectors_s write."
            info "Disk IO ticks for $part, ms/s:" \
                 "$read_ms_s read, $write_ms_s write."
            info "Disk IO queue for $part, ms/s:" \
                 "$io_ms_s active, $w_io_ms_s weighted."
        else
            warn "No previous disk record for $part in the snapshot file."
        fi

        error=$((
            sed -i -r "/${snap_regex}/d" $MEASURE_SYSTEM_SNAP_FILE && \
            echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
            die "Can not save the disk snapshot for $part: $error."
    else
        die "Can not match the disk data for $part."
    fi

    # disk space

    if [ -z $(grep $part /proc/swaps | cut -d ' ' -f 1) ]; then
        src_regex="$part (\S+) (\S+) (\S+) (\S+) (\S+)$"
        src=$((
            df | sed -r 's/\s+/ /g' | grep -E "$part " | \
            xargs -l bash -c "$( \
                echo 'echo $(ls -l $0 | sed -r 's/.* //' 2>/dev/null ||' \
                     'echo $0) $1 $2 $3 $4 $5 $6')"
            ) 2>&1) ||
            die "Can not get a disk space data for $part: $src."

        if [[ $src =~ $src_regex ]]; then
            src_total=${BASH_REMATCH[1]}
            src_used=${BASH_REMATCH[2]}
            src_available=${BASH_REMATCH[3]}
            src_percent=${BASH_REMATCH[4]}
            src_path=${BASH_REMATCH[5]}

            info "Disk space for $part $src_path, kB:" \
                 "$src_total total, $src_used used, $src_available available," \
                 "$src_percent."
        else
            die "Can not match the disk space data for $part."
        fi
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
    src_regex="$iface: (\S+) (\S+) (\S+) \S+ \S+ \S+ \S+ \S+ (\S+) (\S+) (\S+) "
    src=$((
        cat /proc/net/dev | sed -r 's/\s+/ /g' | sed -r 's/^ //g' | \
        grep -E "$src_regex" ) 2>&1) ||
        die "Can not get a network data for $iface: $src."
    src_time=$(date +%s)

    if [[ $src =~ $src_regex ]]; then
        src_bytes_received=${BASH_REMATCH[1]}
        src_packets_received=${BASH_REMATCH[2]}
        src_errors_received=${BASH_REMATCH[3]}
        src_bytes_sent=${BASH_REMATCH[4]}
        src_packets_sent=${BASH_REMATCH[5]}
        src_errors_sent=${BASH_REMATCH[6]}

        snap_regex="(\S+) $src_regex"
        snap=$(grep -E "$src_regex" $MEASURE_SYSTEM_SNAP_FILE)

        if [[ $snap =~ $snap_regex ]]
        then
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
                 "$bytes_received_s received, $bytes_sent_s sent."
            info "Network packets for $iface, /s:" \
                 "$packets_received_s received, $packets_sent_s sent."
            info "Network errors for $iface, /s:" \
                 "$errors_received_s received, $errors_sent_s sent."
        else
            warn "No previous network record for $iface in the snapshot file."
        fi

        error=$((
            sed -i -r "/${snap_regex}/d" $MEASURE_SYSTEM_SNAP_FILE && \
            echo "$src_time $src" >> $MEASURE_SYSTEM_SNAP_FILE) 2>&1) ||
            die "Can not save the network snapshot for $iface: $error."
    else
        die "Can not match the network data for $iface."
    fi
done
