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

[[ ! -z "$SCHEMA_ACTION" ]] && ! contains 'dump commit' "$SCHEMA_ACTION"  && \
    die "$(declare -pA a=(
        ['1/message']='Wrong SCHEMA_ACTION specified'
        ['2/schema_action']=$SCHEMA_ACTION))"

if [[ "$SCHEMA_ACTION" == 'dump' ]] || [[ -z "$SCHEMA_ACTION" ]]; then
    error=$(mkdir -p $SCHEMA_DIR 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not make a schema directory'
            ['2/schema_dir']=$SCHEMA_DIR
            ['3m/detail']=$error))"

    error=$($PGDUMPALL -g -f $SCHEMA_DIR/globals.sql 2>&1) ||
        die "$(declare -pA a=(
            ['1/message']='Can not dump globals'
            ['2m/detail']=$error))"

    for dbname in $SCHEMA_DBNAME_LIST; do
        exclude_schema_list=$(
            $PSQL -XAt -R ' -N ' -c "$SCHEMA_EXCLUDE_SCHEMA_SQL" \
                $dbname 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a schema list for exclusion'
                ['2m/detail']=$exclude_schema_list))"

        if [[ ! -z "$exclude_schema_list" ]]; then
            exclude_schema_list="-N $exclude_schema_list"
        fi

        exclude_table_list=$(
            $PSQL -XAt -R ' -T ' -F '.' -c "$SCHEMA_EXCLUDE_TABLE_SQL" \
                $dbname 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not get a table list for exclusion'
                ['2m/detail']=$exclude_table_list))"

        if [ ! -z "$exclude_table_list" ]; then
            exclude_table_list="-T $exclude_table_list"
        fi

        error=$(
            $PGDUMP -s $exclude_schema_list $exclude_table_list \
                -f $SCHEMA_DIR/$dbname.sql $dbname 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not dump the database'
                ['2/database']=$dbname
                ['3m/detail']=$error))"

        info "$(declare -pA a=(
            ['1/message']='Dump has been created'
            ['2/database']=$dbname))"
    done
fi

if [[ "$SCHEMA_ACTION" == 'commit' ]] || [[ -z "$SCHEMA_ACTION" ]]; then
    commit_cmd=$(cat <<EOF
cd $SCHEMA_DIR &&
$GIT add . && $GIT diff --cached --exit-code --quiet ||
($GIT commit -m 'Updated DDL.' && $GIT pull -r && $GIT push)
EOF
    )

    if [[ -z "$SCHEMA_SSH_KEY" ]]; then
        result=$(bash -c "$commit_cmd" 2>&1) ||
            die "$(declare -pA a=(
                ['1/message']='Can not commit changes'
                ['2m/detail']=$result))"
    else
        result=$(
            $SSHAGENT bash \
            -c "$SSHADD $SCHEMA_SSH_KEY && $commit_cmd" 2>&1) || \
            die "$(declare -pA a=(
                ['1/message']='Can not commit changes'
                ['2m/detail']=$result))"
    fi

    regexp='(\S+) files? changed(, (\S+) insertions?...)?(, (\S+) deletions?...)?'

    if [[ "$result" =~ $regexp ]]; then
        file_count=${BASH_REMATCH[1]}
        insert_count=${BASH_REMATCH[3]}
        delete_count=${BASH_REMATCH[5]}

        info "$(declare -pA a=(
            ['1/message']='Changes found and commited'
            ['2/file_count']=${files_count:-null}
            ['3/insert_count']=${insert_count:-null}
            ['4/delete_count']=${delete_count:-null}))"
    else
        info "$(declare -pA a=(
            ['1/message']='No changes found'))"
    fi
fi
