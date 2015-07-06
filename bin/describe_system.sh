#!/bin/bash

# describe_system.sh - provides details about system components.
#
# Collects and prints out:
#
# - general system info
# - distribution
# - CPU info
# - memory and swap
# - filesystem info
# - network info
# - custom kernel settings
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# general system info OS, kernel version, architecture

(
    src=$(uname -a)

    regex='^(\S+) \S+ (\S+) .+ (\S+) \S+$'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the genral system info data'
            ['2m/data']=$src))"

    os=${BASH_REMATCH[1]}
    kernel=${BASH_REMATCH[2]}
    arch=${BASH_REMATCH[3]}

    info "$(declare -pA a=(
        ['1/message']='General system info'
        ['2/os']=$os
        ['3/kernel']=$kernel
        ['4/arch']=$arch))"
)

# distribution name, version

(
    src=$(
        (cat /etc/*release | grep -iE '^(name|version_id)=' \
            | sed -r 's/(.*=|")//g' | paste -sd ' ') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a distribution data'
            ['2m/detail']=$src))"

    regex='(\S*) (\S*)'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the distribution data'
            ['2m/data']=$src))"

    name=${BASH_REMATCH[1]:-null}
    version=${BASH_REMATCH[2]:-null}

    info "$(declare -pA a=(
        ['1/message']='Distribution'
        ['2/name']=$name
        ['3/version']=$version))"
)

# CPU model, cache, threads, cores

(
    src=$(
        (cat /proc/cpuinfo \
            | grep -E 'model name|cache size|cpu cores|processor' \
            | tail -n 4 | sed -r 's/.*:\s*//' | paste -sd ' ') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a CPU data'
            ['2m/detail']=$src))"

    regex='^(\S+) (.+) (\S+) \S+ (\S+)$'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the CPU data'
            ['2m/data']=$src))"

    threads=$(( ${BASH_REMATCH[1]} + 1 ))
    model=${BASH_REMATCH[2]}
    cache=${BASH_REMATCH[3]}
    cores=${BASH_REMATCH[4]}

    info "$(declare -pA a=(
        ['1/message']='CPU info'
        ['2/model']=$model
        ['3/cache']=$cache
        ['4/threads']=$threads
        ['5/cores']=$cores))"
)

# memory total, swap

(
    src=$(
        (cat /proc/meminfo | grep -iE '^(Mem|Swap)Total:' \
            | sed -r 's/.+:\s+| kB//g' | paste -sd ' ') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a memory data'
            ['2m/detail']=$src))"

    regex='(\S+) (\S+)'

    [[ $src =~ $regex ]] ||
        die "$(declare -pA a=(
            ['1/message']='Can not match the memory data'
            ['2m/data']=$src))"

    memory=${BASH_REMATCH[1]}
    swap=${BASH_REMATCH[2]}

    info "$(declare -pA a=(
        ['1/message']='Memory info, kB'
        ['2/memory']=$memory
        ['3/swap']=$swap))"
)

# filesystem mount point, device, type, options, disk space, usage

part_list=$(lsblk -ro KNAME,TYPE | grep ' part' | sed 's/ .*//' | sort)

for part in $part_list; do
    if [[ ! -z "$(df | grep $part | cut -d ' ' -f 1)" ]]; then
        (
            regex="(\S+) (\S+) (\S+)% (\S+) (\S+) \((\S+)\)"
            src=$(
                join -o '1.1 1.2 1.5 1.6 2.5 2.6' \
                    <(df 2>/dev/null | sed -r 's/\s+/ /g' \
                      | grep -E "$part " | sort | xargs -l bash -c "$( \
                          echo 'echo $(ls -l $0 | sed -r 's/.* //' \
                          2>/dev/null || echo $0) $1 $2 $3 $4 $5 $6')") \
                    <(mount -l | sort))

            [[ $src =~ $regex ]] ||
                die "$(declare -pA a=(
                    ['1/message']='Can not match the partition data'
                    ['2/partition']=$part
                    ['3m/detail']=$src))"

            device=${BASH_REMATCH[1]}
            disk_space=${BASH_REMATCH[2]}
            usage_percent=${BASH_REMATCH[3]}
            mount_point=${BASH_REMATCH[4]}
            type=${BASH_REMATCH[5]}
            options=${BASH_REMATCH[6]}

            info "$(declare -pA a=(
                ['1/message']='Partition'
                ['2/name']=$part
                ['3/mount_point']=$mount_point
                ['4/type']=$type
                ['5/options']=$options
                ['6/disk_space']=$disk_space
                ['7/usage_percent']=$usage_percent))"
        )
    fi
done

# network interface MTU, status, MAC, IP, IPv6

(
    src_list=$(
        (echo $(ip addr) | sed -r 's/\S+: \S+:/\n\0/g' | sed '/^$/d;') 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not get a network interface source list'
            ['2m/detail']=$src_list))"

    while read src; do
        (
            [[ $src =~ $(echo ': (\S+):') ]] ||
                die "$(declare -pA a=(
                    ['1/message']='Can not match the network interface name'
                    ['2m/detail']=$src))"

            name=${BASH_REMATCH[1]}

            [[ $src =~ $(echo 'mtu (\S+)') ]]; mtu=${BASH_REMATCH[1]:-null}
            [[ $src =~ $(echo 'state (\S+)') ]]; state=${BASH_REMATCH[1]:-null}
            [[ $src =~ $(echo 'link/\S+ (\S+)') ]]; link=${BASH_REMATCH[1]:-null}
            [[ $src =~ $(echo 'inet (\S+)') ]]; inet=${BASH_REMATCH[1]:-null}
            [[ $src =~ $(echo 'inet6 (\S+)') ]]; inet6=${BASH_REMATCH[1]:-null}

            info "$(declare -pA a=(
                ['1/message']='Network interface'
                ['2/name']=$name
                ['3/mtu']=$mtu
                ['4/state']=$state
                ['5/link']=$link
                ['6/inet']=$inet
                ['7/inet6']=$inet6))"
        )
    done <<< "$src_list"
)

# custom kernel settings

(
    result=$(
        cat /run/sysctl.d/*.conf /etc/sysctl.d/*.conf \
            /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf \
            /lib/sysctl.d/*.conf /etc/sysctl.conf 2>/dev/null \
            | sort | sed -r 's/\s*=\s*/=/g'| sed -r 's/\s*#.*//g' \
            | grep -vE '^\s*$')

    declare -A a=(
        ['1/message']='Custom kernel settings')

    count=2
    while read l; do
        a["$count/${l%%=*}"]="${l#*=}"
        (( count++ ))
    done <<< "$result"

    info "$(declare -p a)"
)
