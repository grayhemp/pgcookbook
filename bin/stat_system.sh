#!/bin/bash

# stat_system.sh - system statistics collecting script.
#
# Collects and prints out:
#
# - load average 1, 5, 15
# - CPU user, nice, system, idle, iowait, other
# - memory total, used, free, buffers, cached
# - swap total, used, free
# - context switch count
# - pages in, out
# - swap pages in, out
# - disk IO count read, write
# - disk IO size read, write
# - disk IO time read, write
# - disk IO request queue time, weighted time
# - disk space
# - network bytes sent and received
# - network packets sent and received
# - network errors
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

touch $STAT_SYSTEM_FILE

# load average 1, 5, 15

(
    src=$(cat /proc/loadavg)

    IFS=$' ' read -r -a l <<< "$src"
    info "$(declare -pA a=(
        ['1/message']='Load average'
        ['2/1min']=${l[0]}
        ['3/5min']=${l[1]}
        ['4/15min']=${l[2]}))"
)

# CPU user, nice, system, idle, iowait, other

(
    src=$(grep -E '^cpu ' /proc/stat | sed -r 's/^cpu +//')

    IFS=$' ' read -r -a l <<< "$src"
    declare -A stat=(
        ['time']=$(date +%s)
        ['user']=${l[0]}
        ['nice']=${l[1]}
        ['system']=${l[2]}
        ['idle']=${l[3]}
        ['iowait']=${l[4]:-0}
        ['irq']=${l[5]:-0}
        ['softirq']=${l[6]:-0}
        ['steal']=${l[7]:-0}
        ['guest']=${l[8]:-0}
        ['guest_nice']=${l[9]:-0})

    regex='declare -A cpu_stat='

    snap_src=$(grep "$regex" $STAT_SYSTEM_FILE | sed 's/cpu_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous CPU stat record in the snapshot file'))"
    else
        eval "$snap_src"

        user_int=$(( ${stat['user']} - ${snap['user']} ))
        nice_int=$(( ${stat['nice']} - ${snap['nice']} ))
        system_int=$(( ${stat['system']} - ${snap['system']} ))
        idle_int=$(( ${stat['idle']} - ${snap['idle']} ))
        iowait_int=$(( ${stat['iowait']} - ${snap['iowait']} ))
        irq_int=$(( ${stat['irq']} - ${snap['irq']} ))
        softirq_int=$(( ${stat['softirq']} - ${snap['softirq']} ))
        steal_int=$(( ${stat['steal']} - ${snap['steal']} ))
        guest_int=$(( ${stat['guest']} - ${snap['guest']} ))
        guest_nice_int=$(( ${stat['guest_nice']} - ${snap['guest_nice']} ))

        total_int=$((
            $user_int + $nice_int + $system_int + $idle_int + $iowait_int +
            $irq_int + $softirq_int + $steal_int + $guest_int + $guest_nice_int
        ))

        user=$(echo $user_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        nice=$(echo $nice_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        system=$(echo $system_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        idle=$(echo $idle_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        iowait=$(echo $iowait_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        irq=$(echo $irq_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        softirq=$(echo $softirq_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        steal=$(echo $steal_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        guest=$(echo $guest_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')
        guest_nice=$(echo $guest_nice_int $total_int \
            | awk '{printf "%.2f", 100 * $1 / $2}')

        info "$(declare -pA a=(
                ['1/message']='CPU usage, %'
                ['2/user']=$user
                ['3/nice']=$nice
                ['4/system']=$system
                ['5/idle']=$idle
                ['6/iowait']=$iowait
                ['7/irq']=$irq
                ['8/softirq']=$softirq
                ['9/steal']=$steal
                ['10/guest']=$guest
                ['11/guest_nice']=$guest_nice))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_SYSTEM_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the CPU data snapshot'
            ['2m/detail']=$error))"
)

# memory total, used, free, buffers, cached
# swap total, used, free
# See http://momjian.us/main/blogs/pgblog/2012.html#May_2_2012

(
    src=$(
        grep -E '^(Mem(Total|Free)|Buffers|Cached|Swap(Total|Free)):' \
            /proc/meminfo \
            | sed -r 's/\s+/ /g' | cut -d ' ' -f 2 | paste -sd ' ')

    IFS=$' ' read -r -a l <<< "$src"
    info "$(declare -pA a=(
        ['1/message']='Memory size, kB'
        ['2/total']=${l[0]}
        ['3/used']=$(( ${l[0]} - ${l[1]} - ${l[2]} - ${l[3]} ))
        ['4/free']=${l[1]}
        ['5/buffers']=${l[2]}
        ['6/cached']=${l[3]}))"

    info "$(declare -pA a=(
        ['1/message']='Swap size, kB'
        ['2/total']=${l[4]}
        ['3/used']=$(( ${l[4]} - ${l[5]} ))
        ['4/free']=${l[5]}))"
)

# context switch count

(
    src=$(grep -E "^ctxt " /proc/stat | cut -d ' ' -f 2)

    IFS=$' ' read -r -a l <<< "$src"
    declare -A stat=(
        ['time']=$(date +%s)
        ['cswitch']=${l[0]})

    regex='declare -A cswitch_stat='

    snap_src=$(grep "$regex" $STAT_SYSTEM_FILE | sed 's/cswitch_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous context switch record in the snapshot file'))"
    else
        eval "$snap_src"

        count_s=$((
            (${stat['cswitch']} - ${snap['cswitch']}) /
            (${stat['time']} - ${snap['time']}) ))

        info "$(declare -pA a=(
                ['1/message']='Context switch, /s'
                ['2/value']=$count_s))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_SYSTEM_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the context switch data snapshot'
            ['2m/detail']=$error))"
)

# pages in, out
# swap pages in, out

(
    src=$(
        grep -E "^(pgpg|pswp)(in|out) " /proc/vmstat | cut -d ' ' -f 2 \
            | paste -sd ' ')

    IFS=$' ' read -r -a l <<< "$src"
    declare -A stat=(
        ['time']=$(date +%s)
        ['in']=${l[0]}
        ['out']=${l[1]}
        ['swap_in']=${l[2]}
        ['swap_out']=${l[3]})

    regex='declare -A pages_stat='

    snap_src=$(grep "$regex" $STAT_SYSTEM_FILE | sed 's/pages_stat/snap/')

    if [[ -z "$snap_src" ]]; then
        warn "$(declare -pA a=(
            ['1/message']='No previous paging record in the snapshot file'))"
    else
        eval "$snap_src"

        interval=$(( ${stat['time']} - ${snap['time']} ))

        in_s=$(( (${stat['in']} - ${snap['in']}) / $interval ))
        out_s=$(( (${stat['out']} - ${snap['out']}) / $interval ))
        swap_in_s=$(( (${stat['swap_in']} - ${snap['swap_in']}) / $interval ))
        swap_out_s=$((
            (${stat['swap_out']} - ${snap['swap_out']}) / $interval ))

        info "$(declare -pA a=(
                ['1/message']='Page count, /s'
                ['2/in']=$in_s
                ['3/out']=$out_s))"

        info "$(declare -pA a=(
                ['1/message']='Swap page count, /s'
                ['2/in']=$swap_in_s
                ['3/out']=$swap_out_s))"
    fi

    error=$((
        sed -i "/$regex/d" $STAT_SYSTEM_FILE &&
            declare -p stat | sed "s/declare -A stat=/$regex/" \
            >> $STAT_SYSTEM_FILE) 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not save the paging data snapshot'
            ['2m/detail']=$error))"
)

# Processing partition stats

part_list=$(lsblk -ro KNAME,TYPE | grep ' part' | sed 's/ .*//' | sort | uniq)

for part in $part_list; do
    # disk IO count read, write
    # disk IO size read, write
    # disk IO time read, write
    # disk IO request queue time, weighted time
    # https://www.kernel.org/doc/Documentation/iostats.txt
    # https://www.kernel.org/doc/Documentation/block/stat.txt

    (
        src=$(
            grep -E " $part " /proc/diskstats | sed -r 's/\s+/ /g' \
                | sed -r 's/^\s//g')

        IFS=$' ' read -r -a l <<< "$src"
        declare -A stat=(
            ['time']=$(date +%s)
            ['read']=${l[3]}
            ['read_merged']=${l[4]}
            ['read_sectors']=${l[5]}
            ['read_ms']=${l[6]}
            ['write']=${l[7]}
            ['write_merged']=${l[8]}
            ['write_sectors']=${l[9]}
            ['write_ms']=${l[10]}
            ['io_ms']=${l[12]}
            ['w_io_ms']=${l[13]})

        regex="declare -A diskio_${part}_stat="

        snap_src=$(
            grep "$regex" $STAT_SYSTEM_FILE | sed "s/diskio_${part}_stat/snap/")

        if [[ -z "$snap_src" ]]; then
            warn "$(declare -pA a=(
                ['1/message']='No previous disk IO record in the snapshot file'
                ['2/partition']=$part))"
        else
            eval "$snap_src"

            interval=$(( ${stat['time']} - ${snap['time']} ))

            read_s=$(( (${stat['read']} - ${snap['read']}) / $interval ))
            read_merged_s=$((
                (${stat['read_merged']} - ${snap['read_merged']}) / $interval ))
            read_sectors_s=$((
                (${stat['read_sectors']} - ${snap['read_sectors']}) /
                $interval / 2 ))
            read_ms_s=$((
                (${stat['read_ms']} - ${snap['read_ms']}) / $interval ))
            write_s=$(( (${stat['write']} - ${snap['write']}) / $interval ))
            write_merged_s=$((
                (${stat['write_merged']} - ${snap['write_merged']}) /
                $interval ))
            write_sectors_s=$((
                (${stat['write_sectors']} - ${snap['write_sectors']}) /
                $interval / 2))
            write_ms_s=$((
                (${stat['write_ms']} - ${snap['write_ms']}) / $interval ))
            io_ms_s=$(( (${stat['io_ms']} - ${snap['io_ms']}) / $interval ))
            w_io_ms_s=$((
                (${stat['w_io_ms']} - ${snap['w_io_ms']}) / $interval ))

            info "$(declare -pA a=(
                    ['1/message']='Disk IO count, /s'
                    ['2/partition']=$part
                    ['3/read']=$read_s
                    ['4/read_merged']=$read_merged_s
                    ['5/write']=$write_s
                    ['6/write_merged']=$write_merged_s))"

            info "$(declare -pA a=(
                    ['1/message']='Disk IO size, kB/s'
                    ['2/partition']=$part
                    ['3/read']=$read_sectors_s
                    ['4/write']=$write_sectors_s))"

            info "$(declare -pA a=(
                    ['1/message']='Disk IO ticks, ms/s'
                    ['2/partition']=$part
                    ['3/read']=$read_ms_s
                    ['4/write']=$write_ms_s))"

            info "$(declare -pA a=(
                    ['1/message']='Disk IO queue, ms/s'
                    ['2/partition']=$part
                    ['3/active']=$io_ms_s
                    ['4/weighted']=$w_io_ms_s))"
        fi

        error=$((
            sed -i "/$regex/d" $STAT_SYSTEM_FILE &&
                declare -p stat | sed "s/declare -A stat=/$regex/" \
                >> $STAT_SYSTEM_FILE) 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not save the disk IO data snapshot'
                ['2/partition']=$part
                ['3m/detail']=$error))"
    )

    # disk space

    if [[ ! -z "$(df | grep $part | cut -d ' ' -f 1)" ]]; then
        (
            src=$(
                df 2>/dev/null | sed -r 's/\s+/ /g' | grep -E "$part " \
                    | xargs -L 1 bash -c "$( \
                        echo 'echo $(ls -l $0 | sed -r 's/.* //' 2>/dev/null ' \
                        '|| echo $0) $1 $2 $3 $4 $5 $6')")

           IFS=$' ' read -r -a l <<< "$src"
            info "$(declare -pA a=(
                ['1/message']='Disk space, kB'
                ['2/partition']=$part
                ['3/path']="${l[5]}"
                ['4/total']=${l[1]}
                ['5/used']=${l[2]}
                ['6/available']=${l[3]}))"

            info "$(declare -pA a=(
                ['1/message']='Disk space usage, %'
                ['2/partition']=$part
                ['3/path']="${l[5]}"
                ['4/percent']=$(echo ${l[4]} | sed 's/%//')))"
        )
    fi
done

# Processing network interface stats

iface_list=$(
    cat /proc/net/dev | sed -r 's/\s+/ /g' | sed -r 's/^ //g' \
        | grep -E ' *\S+: ' | cut -d ' ' -f 1 | sed 's/://' | sort | uniq)

# network bytes sent and received
# network packets sent and received
# network errors

for iface in $iface_list; do
    (
        src=$(
            grep "$iface: " /proc/net/dev | sed -r 's/\s+/ /g' \
                | sed -r 's/^\s//g')

        IFS=$' ' read -r -a l <<< "$src"
        declare -A stat=(
            ['time']=$(date +%s)
            ['bytes_received']=${l[1]}
            ['packets_received']=${l[2]}
            ['errors_received']=${l[3]}
            ['bytes_sent']=${l[9]}
            ['packets_sent']=${l[10]}
            ['errors_sent']=${l[11]})

        regex="declare -A network_${iface}_stat="

        snap_src=$(
            grep "$regex" $STAT_SYSTEM_FILE \
                | sed "s/network_${iface}_stat/snap/")

        if [[ -z "$snap_src" ]]; then
            warn "$(declare -pA a=(
                ['1/message']='No previous network record in the snapshot file'
                ['2/iface']=$iface))"
        else
            eval "$snap_src"

            interval=$(( ${stat['time']} - ${snap['time']} ))

            bytes_received_s=$((
                (${stat['bytes_received']} - ${snap['bytes_received']}) /
                $interval ))
            packets_received_s=$((
                (${stat['packets_received']} - ${snap['packets_received']}) /
                $interval ))
            errors_received_s=$((
                (${stat['errors_received']} - ${snap['errors_received']}) /
                $interval ))
            bytes_sent_s=$((
                (${stat['bytes_sent']} - ${snap['bytes_sent']}) / $interval ))
            packets_sent_s=$((
                (${stat['packets_sent']} - ${snap['packets_sent']}) /
                $interval ))
            errors_sent_s=$((
                (${stat['errors_sent']} - ${snap['errors_sent']}) / $interval ))

            info "$(declare -pA a=(
                    ['1/message']='Network bytes, B/s'
                    ['2/iface']=$iface
                    ['3/received']=$bytes_received_s
                    ['4/sent']=$bytes_sent_s))"

            info "$(declare -pA a=(
                    ['1/message']='Network packets, /s'
                    ['2/iface']=$iface
                    ['3/received']=$packets_received_s
                    ['4/sent']=$packets_sent_s))"

            info "$(declare -pA a=(
                    ['1/message']='Network errors, /s'
                    ['2/iface']=$iface
                    ['3/received']=$errors_received_s
                    ['4/sent']=$errors_sent_s))"
        fi

        error=$((
            sed -i "/$regex/d" $STAT_SYSTEM_FILE &&
                declare -p stat | sed "s/declare -A stat=/$regex/" \
                >> $STAT_SYSTEM_FILE) 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not save the network data snapshot'
                ['2/iface']=$part
                ['3m/detail']=$error))"
    )
done
