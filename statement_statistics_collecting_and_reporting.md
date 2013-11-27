# PgCookbook - a PostgreSQL documentation project

## Statement Statistics Collecting And Reporting

There is an extension named [pg_stat_statements] in PostgreSQL
distributive. In short, it accumulates statement statistics in a
system view named `pg_stat_statements`. Since the version 9.2 it
started analyzing queries' "fingerprints" and normalizing them. That
made the extension very useful.

There also is a nuance. For each query it increments numbers, like
calls count, total time, etc, since the extension was installed or
pg_stat_statements_reset() was called or pg_stat_statements.save is
set to true and the server was restarted. It means we can not get a
statistics, say, for the yesterday or for an hour after 6 PM. That
issue makes it not very useful, because it is always important to
track the dynamic and trends.

However, there is a solution. We could make snapshots of
`pg_stat_statements` every, say 10 minutes, and collect them to a
separate table. So we will be able to get the statistics for any
period with 10 minutes granularity.

Furthermore, we have the [stat_statements.sh](bin/stat_statements.sh)
script that automates all this stuff. From its description.

    # Requires pg_stat_statements to be installed. Connects to
    # STAT_DBNAME and creats its environment if needed. When
    # STAT_SNAPSHOT is not true it prints a top STAT_N queries
    # statistics report for the period specified with STAT_SINCE and
    # STAT_TILL. If STAT_ORDER is 0 then it will print top most time
    # consuming queries, if 1 then most often called. If STAT_SNAPSHOT
    # is true then it creates a snapshot of current statements
    # statistics and resets it to begin collecting another one.

Below is its configuration example (see
[config.sh.example](bin/config.sh.example)).

    test -z $STAT_SNAPSHOT && STAT_SNAPSHOT=false
    STAT_DBNAME='dbname1'
    test -z $STAT_SINCE && STAT_SINCE=$(date -I)
    test -z $STAT_TILL && STAT_TILL=$(date -I --date='+1 day')
    STAT_N=10
    STAT_ORDER=0

To create snapshots every 10 minutes put the following line to `cron`.

    */10 * * * * STAT_SNAPSHOT=true bash stat_statements.sh

After some amount of snapshots you will be able to get your
statistics. Note the values of `STAT_SINCE` and `STAT_TILL` above. By
default it is configured to get a current day's statistics.

    bash stat_statements.sh

    pos: 1
    time: 14.21%, 62970533.029 ms, 425.385 ms avg
    calls: 0.02%, 148032
    rows: 148032, 1.000 avg
    users: user1, user2
    dbs: dbname1, dbname2

    SELECT test_function1(?)

    pos: 2
    time: 11.33%, 50191888.738 ms, 3297.759 ms avg
    calls: 0.00%, 15220
    rows: 918868, 60.372 avg
    users: cron
    dbs: dbname1

    DELETE FROM table2
    WHERE id IN (
        SELECT id
        FROM table2
        WHERE created < now() - '5 days'::interval
        LIMIT 1000);

    [...]

    pos: 11
    time: 37.18%, 164718282.086 ms, 0.203 ms avg
    calls: 99.68%, 810596736
    rows: 1790421264, 2.209 avg
    users: user1, user2, test
    dbs: dbname1, dbname2, test

However, you can request it for any period you wish by specifying
those variables in the command line.

[pg_stat_statements]: http://www.postgresql.org/docs/current/static/index.html
