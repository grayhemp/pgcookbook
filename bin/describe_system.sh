#!/bin/bash

# describe_system.sh - provides details on general system components.
#
# Prints out an information about CPU, memory, filesystem, kernel,
# etc.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# general info hostname, OS, kernel version, architecture

(
    src=$(uname -a)

    regex='^(\S+) (\S+) (\S+) .+ (\S+) \S+$'

    [[ $src =~ $regex ]] || die "Can not match the genral info data: $src."

    os=${BASH_REMATCH[1]}
    hostname=${BASH_REMATCH[2]}
    kernel=${BASH_REMATCH[3]}
    architecture=${BASH_REMATCH[4]}

    info "General info:" \
         "host $hostname, OS $os, kernel $kernel, arch $architecture."
)

# distribution name, version

(
    src=$(
        cat /etc/*release | grep -iE '^(name|version_id)=' \
        | sed -r 's/(.*=|")//g' | paste -sd ' ')

    regex='(\S*) (\S*)'

    [[ $src =~ $regex ]]

    name=${BASH_REMATCH[1]:-'unknown'}
    version=${BASH_REMATCH[2]:-'unknown'}

    info "Distribution: name $name, version $version."
)

# CPU model, cache, threads, cores

(
    src=$(
        cat /proc/cpuinfo \
        | grep -E 'model name|cache size|cpu cores|processor' \
        | tail -n 4 | sed -r 's/.*:\s*//' | paste -sd ' ')

    regex='^(\S+) (.+) (\S+) \S+ (\S+)$'

    [[ $src =~ $regex ]] || die "Can not match the CPU data: $src."

    threads=$(( ${BASH_REMATCH[1]} + 1 ))
    model=${BASH_REMATCH[2]}
    cache=${BASH_REMATCH[3]}
    cores=${BASH_REMATCH[4]}

    info "CPU: model $model, cache kB $cache, threads $threads, cores $cores."
)

# memory total, swap

(
    src=$(
        cat /proc/meminfo | grep -iE '^(Mem|Swap)Total:' \
        | sed -r 's/.+:\s+| kB//g' | paste -sd ' ')

    regex='(\S+) (\S+)'

    [[ $src =~ $regex ]] || die "Can not match the memory data: $src."

    memory=${BASH_REMATCH[1]}
    swap=${BASH_REMATCH[2]}

    info "Memory, kB: total $memory, swap $swap."
)

# filesystem mount point, device, type, options, disk space, usage

part_list=$(ls -l /dev/disk/by-uuid/* | sed 's/.*\///' | sort)

for part in $part_list; do
    if [ -z $(grep $part /proc/swaps | cut -d ' ' -f 1) ]; then
        (
            regex="(\S+) (\S+) (\S+) (\S+) (\S+) \((\S+)\)"
            src=$(
                join -o '1.1 1.2 1.5 1.6 2.5 2.6' \
                    <(df 2>/dev/null | sed -r 's/\s+/ /g' \
                      | grep -E "$part " | sort | xargs -l bash -c "$( \
                          echo 'echo $(ls -l $0 | sed -r 's/.* //' \
                          2>/dev/null || echo $0) $1 $2 $3 $4 $5 $6')") \
                    <(mount -l | sort))

            [[ $src =~ $regex ]] ||
                die "Can not match the partition data for $part: $src."

            device=${BASH_REMATCH[1]}
            disk_space=${BASH_REMATCH[2]}
            usage=${BASH_REMATCH[3]}
            mount_point=${BASH_REMATCH[4]}
            type=${BASH_REMATCH[5]}
            options=${BASH_REMATCH[6]}

            info "Filesystem for $device:" \
                 "mount point $mount_point, type $type," \
                 "options $options, disk space $disk_space, usage $usage."
        )
    fi
done

# network interface MTU, status, MAC, IP, IPv6

(
    src_list=$(ip addr 2>&1) ||
        die "Can not get a network interface source list: $src_list."
    src_list=$(echo $src_list | sed -r 's/\S+: \S+:/\n\0/g' | sed '/^$/d;')

    while read src; do
        (
            [[ $src =~ $(echo ': (\S+):') ]] ||
                die "Can not match the network interface name: $src."
            name=${BASH_REMATCH[1]}

            [[ $src =~ $(echo 'mtu (\S+)') ]]; mtu=${BASH_REMATCH[1]:-'N/A'}
            [[ $src =~ $(echo 'state (\S+)') ]]; state=${BASH_REMATCH[1]:-'N/A'}
            [[ $src =~ $(echo 'link/\S+ (\S+)') ]]; link=${BASH_REMATCH[1]:-'N/A'}
            [[ $src =~ $(echo 'inet (\S+)') ]]; inet=${BASH_REMATCH[1]:-'N/A'}
            [[ $src =~ $(echo 'inet6 (\S+)') ]]; inet6=${BASH_REMATCH[1]:-'N/A'}

            info "Network interface for $name:" \
                 "mtu $mtu, state $state, link $link, inet $inet, inet6 $inet6."
        )
    done <<< "$src_list"
)

# custom kernel settings

list=$(
    cat /run/sysctl.d/*.conf /etc/sysctl.d/*.conf \
        /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf \
        /lib/sysctl.d/*.conf /etc/sysctl.conf 2>/dev/null \
    | grep -vE '^#|^\s*$' | sort  | paste -sd ',' | sed -r 's/\s*=\s*/ /g' \
    | sed 's/,/, /g')

info "Custom kernel settings: $list."
