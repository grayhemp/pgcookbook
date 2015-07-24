#!/bin/bash

# stat_system_programs.sh - running programs statistics collecting script.
#
# Collects and prints out:
#
# - top programs by CPU
# - top programs by RSS
# - top programs by precesse count
# - top programs by thread count
#
# Recommended running frequency - once per 1 minute.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# top programs by CPU

src=$(
    ps -eo comm,pcpu --no-headers \
        | awk '{ arr[$1] += $2 } END { for (i in arr) { print i, arr[i] } }' \
        | sort -k 2nr \
        | awk 'BEGIN { i = 0 } \
               { if (i < '$STAT_SYSTEM_TOP_N') arr[$1] += $2; \
                 else arr["all the other"] += $2; \
                 i++ } \
               END { for (i in arr) { print i"\t"arr[i] } }' \
        | sort -k 2nr -t $'\t')

while IFS=$'\t' read -r -a l; do
    info "$(declare -pA a=(
        ['1/message']='Top programs by CPU, %'
        ['2/name']=${l[0]}
        ['3/value']=${l[1]}))"
done <<< "$src"

# top programs by RSS

src=$(
    ps -eo comm,rss --no-headers \
        | awk '{ arr[$1] += $2; t += $2 }
               END { for (i in arr) { print i, 100 * arr[i] / t } }' \
        | sort -k 2nr \
        | awk 'BEGIN { i = 0 } \
               { if (i < '$STAT_SYSTEM_TOP_N') arr[$1] += $2; \
                 else arr["all the other"] += $2; \
                 i++ } \
               END { for (i in arr) { printf "%s\t%.2f\n", i, arr[i] } }' \
        | sort -k 2nr -t $'\t')

while IFS=$'\t' read -r -a l; do
    info "$(declare -pA a=(
        ['1/message']='Top programs by RSS, %'
        ['2/name']=${l[0]}
        ['3/value']=${l[1]}))"
done <<< "$src"

# top programs by precesse count

src=$(
    ps -eo comm --no-headers | sort | uniq -c \
        | awk '{ arr[$2] += $1 } END { for (i in arr) { print i, arr[i] } }' \
        | sort -k 2nr \
        | awk 'BEGIN { i = 0 } \
               { if (i < '$STAT_SYSTEM_TOP_N') arr[$1] += $2; \
                 else arr["all the other"] += $2; \
                 i++ } \
               END { for (i in arr) { print i"\t"arr[i] } }' \
        | sort -k 2nr -t $'\t')

while IFS=$'\t' read -r -a l; do
    info "$(declare -pA a=(
        ['1/message']='Top programs by process count'
        ['2/name']=${l[0]}
        ['3/value']=${l[1]}))"
done <<< "$src"

# top programs by thread count

src=$(
    ps -eo comm,nlwp --no-headers \
        | awk '{ arr[$1] += $2 } END { for (i in arr) { print i, arr[i] } }' \
        | sort -k 2nr \
        | awk 'BEGIN { i = 0 } \
               { if (i < '$STAT_SYSTEM_TOP_N') arr[$1] += $2; \
                 else arr["all the other"] += $2; \
                 i++ } \
               END { for (i in arr) { print i"\t"arr[i] } }' \
        | sort -k 2nr -t $'\t')

while IFS=$'\t' read -r -a l; do
    info "$(declare -pA a=(
        ['1/message']='Top programs by thread count'
        ['2/name']=${l[0]}
        ['3/value']=${l[1]}))"
done <<< "$src"
