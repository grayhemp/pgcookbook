#!/bin/bash

# stat_skytools_system.sh - system level Skytools stats collecting
# script.
#
# Collects a variety of system stats for Skytools. Compatible with
# Skytools versions >=3.0.
#
# Copyright (c) 2015 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

# pgqd is running

(
    info "$(declare -pA a=(
        ['1/message']='PgQ daemon is running'
        ['2/value']=$(
            ps --no-headers -C pgqd 1>/dev/null 2>&1 &&
                echo 'true' || echo 'false')))"
)
