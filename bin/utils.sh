#!/bin/bash

# utils.sh - reusable definitions.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

set -o pipefail

source $(dirname $0)/config.sh

# Logging

base_headers=$(declare -Ap a=(
    ['-4/timestamp']=$(date +'%Y-%m-%dT%H:%M:%S%z')
    ['-3/host']=$(hostname)
    ['-2/pid']=$$
    ['-1/facility']=$(basename $0)))

function concat_headers() {
    local arr1
    local arr2
    eval "declare -A arr1=${1#*=}"
    eval "declare -A arr2=${2#*=}"
    for key in "${!arr2[@]}"; do
        arr1["$key"]="${arr2[$key]}"
    done
    arr1['0/level']="$3"
    echo -n "$(declare -p arr1)"
}

function die() {
    local result=$(concat_headers "$base_headers" "$1" 'ERROR')
    echo "$($formatter "$result")" 1>&2
    exit 1
}

function warn() {
    local result=$(concat_headers "$base_headers" "$1" 'WARNING')
    echo "$($formatter "$result")" 1>&2
}

function note() {
    local result=$(concat_headers "$base_headers" "$1" 'NOTICE')
    echo "$($formatter "$result")"
}

function info() {
    local result=$(concat_headers "$base_headers" "$1" 'INFO')
    echo "$($formatter "$result")"
}

function progress() {
    local result=$(concat_headers "$base_headers" "$1" 'PROGRESS')
    echo -n "$($formatter "$result")"
    echo -ne "\r"
}

# Structures

function contains() {
    local item
    for item in $1; do
        if [[ "$2" = "$item" ]]; then
            return 0
        fi
    done

    return 1
}

# Formatting
#
# recognized terms
#
# declare -A a=(
#     ['string']='Lorem ipsum.'
#     ['number']=123.45
#     ['true']=true
#     ['false']=false
#     ['null']=null
#     ['empty_string']='')
#
# key flags
#
# [Nm/]name
#
# N - key order, eg. -2 or 14
# m - for multiline values with the 'plain' format

function to_plain() {
    local arr
    eval "declare -A arr=${1#*=}"

    local index=1
    local key

    local key_list=$(for key in "${!arr[@]}"; do echo "$key"; done | sort -n)

    while read key; do
        [[ "$key" =~ ^(.+?\/)?(.+)$ ]]
        local key_flags="${BASH_REMATCH[1]}"
        local key_name="${BASH_REMATCH[2]}"

        local key_str
        if ! contains 'timestamp host facility level pid message' "$key_name"
        then
            key_str="$key_name="
        fi

        if [[ "$key_flags" =~ m ]]; then
            echo -en "$key_str<<EOS\n"
            echo -en "${arr[$key]}"
            echo -en "\nEOS"
            (( ${#arr[@]} != $index )) && echo -ne "\n"
        elif [[ "$key_name" == 'message' ]]; then
            printf '%s%s' "$key_str" "${arr[$key]}"
            (( ${#arr[@]} > 6 )) && echo -ne ":"
        elif contains 'timestamp host facility level pid' "$key_name"; then
            printf '%s%s' "$key_str" "${arr[$key]}"
        else
            printf '%s%s' "$key_str" "$(to_kv_token "${arr[$key]}")"
        fi

        if [[ ! "$key_flags" =~ m ]]; then
            (( ${#arr[@]} != $index )) && echo -n ' '
        fi
        (( index++ ))
    done <<< "$key_list"
}

function to_kv() {
    local arr
    eval "declare -A arr=${1#*=}"

    local index=1
    local key

    local key_list=$(for key in "${!arr[@]}"; do echo "$key"; done | sort -n)

    while read key; do
        [[ "$key" =~ ^(.+?\/)?(.+)$ ]]
        local key_flags="${BASH_REMATCH[1]}"
        local key_name="${BASH_REMATCH[2]}"

        printf '%s=%s' "$key_name" "$(to_kv_token "${arr[$key]}")"
        (( ${#arr[@]} != $index )) && echo -n ' '
        (( index++ ))
    done <<< "$key_list"
}

function to_kv_token() {
    if [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo -n "$1"
    elif [[ "$1" =~ ^[a-Z0-9_-:.]+$ ]]; then
        echo -n "$1"
    elif [[ "$1" =~ \"|\010|\f|\n|\r|\t ]]; then
        v="$(printf '%s' "$1" \
            | sed -r 's/(\"|\010|\f|$|\r|\t)/\\\1/g' \
            | tr \\010\\f\\n\\r\\t bfnrt | sed 's/\\$//')"
        printf '"%s"' "$v"
    else
        printf '"%s"' "$1"
    fi
}

function to_json() {
    local arr
    eval "declare -A arr=${1#*=}"

    echo -n '{'

    local index=1
    local key

    local key_list=$(for key in "${!arr[@]}"; do echo "$key"; done | sort -n)

    while read -r key; do
        [[ "$key" =~ ^(.+?\/)?(.+)$ ]]
        local key_flags="${BASH_REMATCH[1]}"
        local key_name="${BASH_REMATCH[2]}"

        printf '"%s": %s' "$key_name" "$(to_json_value "${arr[$key]}")"
        (( ${#arr[@]} != $index )) && echo -n ', '
        (( index++ ))
    done <<< "$key_list"

    echo -n '}'
}

function to_json_value() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -n "$1"
    elif [[ -z "$1" ]]; then
        echo -n '""'
    elif contains 'true false null' "$1"; then
        echo -n "$1"
    elif [[ "$1" =~ \"|\\|\/|\010|\f|\n|\r|\t ]]; then
        v="$(printf '%s' "$1" \
            | sed -r 's/(\"|\\|\/|\010|\f|$|\r|\t)/\\\1/g' \
            | tr \\010\\f\\n\\r\\t bfnrt | sed 's/\\$//')"
        printf '"%s"' "$v"
    else
        printf '"%s"' "$1"
    fi
}

if contains "plain kv json" "$LOG_FORMAT"; then
    formatter="to_$LOG_FORMAT"
else
    formatter='to_plain'
    die "$(declare -pA a=(
        ['1/message']='Wrong log format'
        ['2/log_format']=$LOG_FORMAT))"
fi

# Input

function readall() {
    local line
    while read line; do
        sql="$sql\n$line"
    done
    echo -e $sql
}

# Timer

function timer() {
    echo $(( $(date '+%s') - ${1:-0} ))
}
