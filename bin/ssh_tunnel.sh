#!/bin/bash

# ssh_tunnel.sh - a SSH tunneling with compression.
#
# Forwards localhost::TUNNEL_PORT on TUNNEL_HOST to
# localhost::TUNNEL_HOST_PORT on the local side over SSH tunneling
# with compression using TUNNEL_COMP_LEVEL. It assumes that SSH
# without password is configured between servers. The script was made
# for running as a cron job and exits normally if another instance is
# running with the same TUNNEL_LOCK_FILE. In case of network failures
# it attempts to re-establish connection after TUNNEL_RETRY_DELAY.
#
# Copyright (c) 2013 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

(
    flock -xn 543
    if [ $? != 0 ]; then
        info "$(declare -pA a=(
            ['1/message']='Exiting due to another running instance'))"
        exit 0
    fi

    info "$(declare -pA a=(
        ['1/message']='Starting an SSH tunnel'))"

    error=$(
        $SSH -R localhost:$TUNNEL_PORT:localhost:$TUNNEL_HOST_PORT \
            $TUNNEL_HOST -C -o ExitOnForwardFailure=yes \
            -o CompressionLevel=$TUNNEL_COMP_LEVEL \
            "while nc -zv localhost $TUNNEL_PORT; \
             do sleep $TUNNEL_RETRY_DELAY; done" 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Problem occured with the SSH tunnel'
            ['2m/detail']=$error))"
) 543>$TUNNEL_LOCK_FILE
