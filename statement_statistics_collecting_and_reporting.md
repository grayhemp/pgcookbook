# PgCookbook - a PostgreSQL documentation project

## Statement Statistics Collecting and Reporting

There is an extension named [pg_stat_statements] in PostgreSQL
distributive. In short, it accumulates statement statistics accessible
via the system view named `pg_stat_statements`. Since the version 9.2
it started normalizing queries' according to their "fingerprints" what
made the extension very useful to query monitoring and performance
analysis.

However, as every generic system, it requires some extra work to be
done to make it practically convenient. Let's start with the details
of how it works. For each query it accumulates counts, like calls,
total time, IO time. It has been constantly doing that since the
extension was installed, or the statistics was reset by
`pg_stat_statements_reset()` call, or `pg_stat_statements.save` was
set to `off` and the server was restarted. It means that we can't get
slices of statistics, eg., for a day yesterday or for an hour after 6
AM. That issue makes the extension not always convenient for tracking
dynamics and trends, that is very important.

However, there is a workaround. We could make snapshots of
`pg_stat_statements` every, say 10 minutes, and collect them in a
separate table. This way we will be able to get the statistics for any
period with 10 minutes granularity. [PgCookbook](README.md) has the
[stat_statements.sh](bin/stat_statements.sh) script that automates all
this functionality. It can even snapshot and save the snapshots from
read-only replica servers on master with help of the `dblink`
extension, so you could easily track your replica trends either.

This is the documentation string.

    The script connects to STAT_DBNAME, creates its own environment,
    pg_stat_statements and dblink extensions. When STAT_SNAPSHOT is
    not true it prints a top STAT_N queries statistics report for the
    period specified with STAT_SINCE and STAT_TILL. When STAT_ORDER is
    0 - it prints the top most time consuming queries, 1 - the most
    often called, 2 - the most IO consuming ones. If STAT_SNAPSHOT is
    true then it creates a snapshot of current statements statistics,
    resets it to begin collecting another one and clean snapshots that
    are older than and period. If STAT_REPLICA_DSN is specified it
    performs the operation on this particular streaming replica. Do
    not put dbname in the STAT_REPLICA_DSN it will be substituted as
    STAT_DBNAME, automatically. Compatible with PostgreSQL >=9.2.

The configuration should be in the `config.sh` file under the `/bin`
directory. The script specific settings are explained below. For all
the settings see [config.sh.example](bin/config.sh.example).

    STAT_DBNAME='dbname1'
    test -z "$STAT_REPLICA_DSN" && STAT_REPLICA_DSN=
    test -z "$STAT_SNAPSHOT" && STAT_SNAPSHOT=false
    test -z "$STAT_SINCE" && STAT_SINCE=$(date -I)
    test -z "$STAT_TILL" && STAT_TILL=$(date -I --date='+1 day')
    test -z "$STAT_N" && STAT_N=10
    test -z "$STAT_ORDER" && STAT_ORDER=0
    STAT_KEEP_SNAPSHOTS='7 days'

To snapshot statistics every 10 minutes add the following entries to
`crontab` on your master server for the master itself and for each
replica you wish to monitor queries from.

    */10 * * * * STAT_SNAPSHOT=true bash pgcookbook/bin/stat_statements.sh
    */10 * * * * STAT_REPLICA_DSN='host=host2' STAT_SNAPSHOT=true \
                 bash pgcookbook/bin/stat_statements.sh
    */10 * * * * STAT_REPLICA_DSN='host=host3' STAT_SNAPSHOT=true \
                 bash pgcookbook/bin/stat_statements.sh

After some amount of time and snapshots you will be able to request
aggregated statistics for different periods. Note the values of
`STAT_SINCE`, `STAT_TILL`, `STAT_REPLICA_DSN`, `STAT_N` and
`STAT_ORDER` above. By default, if you just run it like `bash
pgcookbook/bin/stat_statements.sh`, you will get the top 10 queries
ordered by total time, longest first, for the current day. To
customize the result you can supply these parameters with your values
in command line, eg. for top 5 most IO consuming queries on `host3`
replica for today, like it is shown below.

    STAT_REPLICA_DSN='host=host3' STAT_N=5 STAT_ORDER=2 \
    bash pgcookbook/bin/stat_statements.sh

    Wed Mar  5 10:19:34 PST 2014  INFO stat_statements.sh:
    Replica report for 'host=host3' ordered by IO time.

    Position: 1
    Time: 14.21%, 62970533.029 ms, 425.385 ms avg
    IO time: 11.2%, 40273527.211 ms, 272.13 ms avg
    Calls: 0.02%, 148032
    Rows: 148032, 1.000 avg
    Users: user1, user2
    Databases: dbname1, dbname2

    SELECT test_function1(?)

    Position: 2
    Time: 11.33%, 50191888.738 ms, 3297.759 ms avg
    IO time: 9,83%, 7935723.653 ms, 452.159 ms avg
    Calls: 0.00%, 15220
    Rows: 918868, 60.372 avg
    Users: cron
    Databases: dbname1

    DELETE FROM table2
    WHERE id IN (
        SELECT id
        FROM table2
        WHERE created < now() - '5 days'::interval
        LIMIT 1000);

    [...]

    Position: 6
    Time: 37.18%, 164718282.086 ms, 0.203 ms avg
    IO time: 30,23%, 127925735.505 ms, 33.502 ms avg
    Calls: 99.68%, 810596736
    Rows: 1790421264, 2.209 avg
    Users: user1, user2, test
    Databases: dbname1, dbname2, test

    other

If you want to receive such reports by email on a daily basis, just
put the calls to `crontab` along with the `MAILTO` directive, like on
the example below.

    MAILTO=dba@company.com,dev@company.com

    59 23 * * * STAT_ORDER=0 bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_ORDER=1 bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_ORDER=2 bash pgcookbook/bin/stat_statements.sh

    59 23 * * * STAT_REPLICA_DSN='host=host2' STAT_ORDER=0 \
                bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_REPLICA_DSN='host=host2' STAT_ORDER=1 \
                bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_REPLICA_DSN='host=host2' STAT_ORDER=2 \
                bash pgcookbook/bin/stat_statements.sh

    59 23 * * * STAT_REPLICA_DSN='host=host3' STAT_ORDER=0 \
                bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_REPLICA_DSN='host=host3' STAT_ORDER=1 \
                bash pgcookbook/bin/stat_statements.sh
    59 23 * * * STAT_REPLICA_DSN='host=host3' STAT_ORDER=2 \
                bash pgcookbook/bin/stat_statements.sh

[pg_stat_statements]: http://www.postgresql.org/docs/current/static/index.html
