#!/bin/bash

# commit_ddl.sh - dumps databases' DDL and adds changes to a Git repo.
#
# Dumps DDL for databases specified in DDL_DBNAME_LIST to DDl_DIR,
# that is assumed to be in a Git repo, stashes changes, pulls, applies
# stashed, commits and pushes them to the Git repo. Shemas and tables
# to exclude can be defined with DDl_EXCLUDE_SCHEMA_SQL and
# DDl_EXCLUDE_TABLE_SQL respectively. If DDL_SSH_KEY is specified the
# script performs Git operations with ssh-agent adding this key first.
# If DDL_ACTION is empty both dumping and Git operations are
# performed, if 'dump' then dumps only, anf if 'commit' then Git
# only. It was done in case if one needs to do those actions
# separately, eg. from different servers.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

test ! -z $DDL_ACTION && ! contains "dump commit" $DDL_ACTION  && \
    die "Wrong DDL_ACTION '$DDL_ACTION' is specified."

if [ "$DDL_ACTION" == 'dump' ] || [ -z "$A" ]; then
    error=$(mkdir -p $DDL_DIR 2>&1) ||  \
        die "Can not make schema directory $DDL_DIR: $error."

    error=$($PGDUMPALL -g -f $DDL_DIR/globals.sql 2>&1) || \
        die "Can not dump globals: $error."

    for dbname in $DDL_DBNAME_LIST; do
        exclude_schema_list=$( \
            $PSQL -XAt -R ' -N ' -c "$DDL_EXCLUDE_SCHEMA_SQL" $dbname 2>&1) || \
            die "Can not get a schema list to exclude: $exclude_schema_list."

        if [ ! -z "$exclude_schema_list" ]; then
            exclude_schema_list="-N $exclude_schema_list"
        fi

        exclude_table_list=$( \
            $PSQL -XAt -R ' -T ' -F '.' \
                  -c "$DDL_EXCLUDE_TABLE_SQL" $dbname 2>&1) || \
            die "Can not get a table list to exclude: $exclude_table_list."

        if [ ! -z "$exclude_table_list" ]; then
            exclude_table_list="-T $exclude_table_list"
        fi

        error=$(
            $PGDUMP -s $exclude_schema_list $exclude_table_list \
                    -f $DDL_DIR/$dbname.sql $dbname 2>&1) || \
            die "Can not dump database $dbname: $error."

        info "Dumps has been created: $dbname."
    done
fi

if [ "$DDL_ACTION" == 'commit' ] || [ -z "$DDL_ACTION" ]; then
    commit_cmd=$(cat <<EOF
cd $DDL_DIR &&
$GIT stash && $GIT pull && $GIT stash pop && \
$GIT add . && $GIT commit -m 'Updated DDL.' && $GIT push
EOF
    )

    if [ -z "$DDL_SSH_KEY" ]; then
        # error=$(bash -c "$commit_cmd" 2>&1) || \
        #     die "Can not commit changes: $error."
        error=$($GIT stash 2>&1) || \
            die "Can not git stash: $error."
        error=$($GIT pull 2>&1) || \
            die "Can not git  pull: $error."
        error=$($GIT stash pop 2>&1) || \
            die "Can not git stash pop: $error."
    else
        error=$(
            $SSHAGENT bash -c "$SSHADD $DDL_SSH_KEY && $commit_cmd" 2>&1) || \
            die "Can not commit changes: $error."
    fi

    info "Changes has been commited."
fi
