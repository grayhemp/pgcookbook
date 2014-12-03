#!/bin/bash

# commit_schema.sh - dumps DB schemas and adds changes to a Git repo.
#
# Dumps schemas for databases specified in SCHEMA_DBNAME_LIST to
# SCHEMA_DIR, that is assumed to be in a Git repo, stashes changes,
# pulls, applies stashed, commits and pushes them to the Git
# repo. Shemas and tables to exclude can be defined with
# SCHEMA_EXCLUDE_SCHEMA_SQL and SCHEMA_EXCLUDE_TABLE_SQL
# respectively. If SCHEMA_SSH_KEY is specified the script performs Git
# operations with ssh-agent adding this key first.  If SCHEMA_ACTION
# is empty both dumping and Git operations are performed, if 'dump'
# then dumps only, anf if 'commit' then Git only. It was done in case
# if one needs to do those actions separately, eg. from different
# servers.
#
# Copyright (c) 2014 Sergey Konoplev
#
# Sergey Konoplev <gray.ru@gmail.com>

source $(dirname $0)/config.sh
source $(dirname $0)/utils.sh

test ! -z $SCHEMA_ACTION && ! contains "dump commit" $SCHEMA_ACTION  && \
    die "Wrong SCHEMA_ACTION '$SCHEMA_ACTION' is specified."

if [ "$SCHEMA_ACTION" == 'dump' ] || [ -z "$SCHEMA_ACTION" ]; then
    error=$(mkdir -p $SCHEMA_DIR 2>&1) ||  \
        die "Can not make schema directory $SCHEMA_DIR: $error."

    error=$($PGDUMPALL -g -f $SCHEMA_DIR/globals.sql 2>&1) || \
        die "Can not dump globals: $error."

    for dbname in $SCHEMA_DBNAME_LIST; do
        exclude_schema_list=$( \
            $PSQL -XAt -R ' -N ' -c "$SCHEMA_EXCLUDE_SCHEMA_SQL" \
            $dbname 2>&1) || \
            die "Can not get a schema list to exclude: $exclude_schema_list."

        if [ ! -z "$exclude_schema_list" ]; then
            exclude_schema_list="-N $exclude_schema_list"
        fi

        exclude_table_list=$( \
            $PSQL -XAt -R ' -T ' -F '.' \
                  -c "$SCHEMA_EXCLUDE_TABLE_SQL" $dbname 2>&1) || \
            die "Can not get a table list to exclude: $exclude_table_list."

        if [ ! -z "$exclude_table_list" ]; then
            exclude_table_list="-T $exclude_table_list"
        fi

        error=$(
            $PGDUMP -s $exclude_schema_list $exclude_table_list \
                    -f $SCHEMA_DIR/$dbname.sql $dbname 2>&1) || \
            die "Can not dump database $dbname: $error."

        info "Dump for $dbname has been created."
    done
fi

if [ "$SCHEMA_ACTION" == 'commit' ] || [ -z "$SCHEMA_ACTION" ]; then
    commit_cmd=$(cat <<EOF
cd $SCHEMA_DIR &&
$GIT add . && $GIT diff --cached --exit-code --quiet ||
($GIT commit -m 'Updated DDL.' && $GIT pull -r && $GIT push)
EOF
    )

    if [ -z "$SCHEMA_SSH_KEY" ]; then
        error=$(bash -c "$commit_cmd" 2>&1) || \
            die "Can not commit changes: $error."
    else
        error=$(
            $SSHAGENT bash \
            -c "$SSHADD $SCHEMA_SSH_KEY && $commit_cmd" 2>&1) || \
            die "Can not commit changes: $error."
    fi

    info "Changes has been commited."
fi
