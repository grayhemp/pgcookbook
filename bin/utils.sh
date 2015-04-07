#!/bin/bash

# utils.sh - reusable definitions.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

set -o pipefail

# Logging

function die() {
    local result=$(concat_arrays "$(get_log_headers 'ERROR')" "$1")
    eval "declare -A result=${result#*=}"
    $formatter "$(declare -p result)" 1>&2
    echo
    exit 1
}

function warn() {
    local result=$(concat_arrays "$(get_log_headers 'WARNING')" "$1")
    eval "declare -A result=${result#*=}"
    $formatter "$(declare -p result)" 1>&2
    echo
}

function note() {
    local result=$(concat_arrays "$(get_log_headers 'NOTICE')" "$1")
    eval "declare -A result=${result#*=}"
    $formatter "$(declare -p result)"
    echo
}

function info() {
    local result=$(concat_arrays "$(get_log_headers 'INFO')" "$1")
    eval "declare -A result=${result#*=}"
    $formatter "$(declare -p result)"
    echo
}

function progress() {
    local result=$(concat_arrays "$(get_log_headers 'PROGRESS')" "$1")
    eval "declare -A result=${result#*=}"
    $formatter "$(declare -p result)"
    echo -ne "\r"
}

function get_log_headers() {
    local arr
    declare -A arr=(
        ['-4/timestamp']=$(date +'%Y-%m-%dT%H:%M:%S%z')
        ['-3/host']=$(hostname)
        ['-2/pid']=$$
        ['-1/facility']=$(basename $0)
        ['-0/level']=$1)
    echo -n "$(declare -p arr)"
}

# Structures

function concat_arrays() {
    local arr1
    local arr2
    eval "declare -A arr1=${1#*=}"
    eval "declare -A arr2=${2#*=}"
    for key in "${!arr2[@]}"; do
        arr1["$key"]="${arr2[$key]}"
    done
    echo -n "$(declare -p arr1)"
}

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

function qq() {
    printf '%q' "$1" | sed -r "s/^[$]?'|'$//g" | sed 's/"/\\"/g' \
        | sed "s/\\\'/'/g" | sed 's/\\ / /g' | sed 's/\\,/,/g' \
        | sed -r 's/^(.*)$/"\1"/'
}

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

        if ! contains 'timestamp host facility level pid message' "$key_name"
        then
            echo -n "$(to_plain_token "$key_name")="
        fi

        if [[ "$key_flags" =~ m ]]; then
            echo -ne "<<EOS\n"
            echo -ne "${arr[$key]}"
            echo -ne "\nEOS"
            (( ${#arr[@]} != $index )) && echo -ne "\n"
        elif [[ "$key_name" == 'message' ]]; then
            echo -n "${arr[$key]}"
            (( ${#arr[@]} > 6 )) && echo -ne ":"
        elif contains 'timestamp host facility level pid' "$key_name"; then
            echo -n "${arr[$key]}"
        else
            echo -n "$(to_plain_token "${arr[$key]}")"
        fi

        if [[ ! "$key_flags" =~ m ]]; then
            (( ${#arr[@]} != $index )) && echo -n ' '
        fi
        (( index++ ))
    done <<< "$key_list"
}

function to_plain_token() {
    if [[ -z "$1" ]]; then
        echo -n '""'
    elif [[ "$1" =~ ^[a-Z0-9_]+$ ]]; then
        echo -n "$1"
    else
        qq "$1"
    fi
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

        echo -n "$(to_kv_token "$key_name")=$(to_kv_token "${arr[$key]}")"
        (( ${#arr[@]} != $index )) && echo -n ' '
        (( index++ ))
    done <<< "$key_list"
}

function to_kv_token() {
    if [[ "$1" =~ ^[a-Z0-9_]+$ ]]; then
        echo -n "$1"
    else
        qq "$1"
    fi
}

function to_json() {
    local arr
    eval "declare -A arr=${1#*=}"

    echo -n '{'

    local index=1
    local key

    local key_list=$(for key in "${!arr[@]}"; do echo "$key"; done | sort -n)

    while read key; do
        [[ "$key" =~ ^(.+?\/)?(.+)$ ]]
        local key_flags="${BASH_REMATCH[1]}"
        local key_name="${BASH_REMATCH[2]}"

        echo -n "$(to_json_key "$key_name"): $(to_json_value "${arr[$key]}")"
        (( ${#arr[@]} != $index )) && echo -n ', '
        (( index++ ))
    done <<< "$key_list"

    echo -n '}'
}

function to_json_key() {
    if [[ -z "$1" ]]; then
        formatter='to_text'
        die "$(declare -A a=(
            ['1/message']=$(to_text_token 'Empty JSON keys are not allowed')))"
    fi

    qq "$1"
}

function to_json_value() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -n "$1"
    elif [[ -z "$1" ]]; then
        echo -n '""'
    elif contains 'true false null' "$1"; then
        echo -n "$1"
    else
        qq "$1"
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
