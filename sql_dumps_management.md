# PgCookbook - a PostgreSQL documentation project

## SQL Dumps Management

One of the DBA's most common tasks is to maintain SQL backups. And one
of the most frequent question is what is the best practices of
creating backups, archiving and cleaning them. Of course it depends on
a particular business requirements and technical environment. However,
there is a flexible generic solution that could be configured for
almost every individual case, the automation that build around
`pg_dump` and `pg_dumpall` - [manage_dumps.sh](bin/manage_dumps.sh)

From its documentation.

    # Makes compressed SQL dumps of every database in
    # DUMPS_DBNAME_LIST and an SQL dump of globals to a date-named
    # directory in DUMPS_LOCAL_DIR and then RSYNC this directory to
    # DUMPS_ARCHIVE_DIR, removing outdated ones from DUMPS_ARCHIVE_DIR
    # based on DUMPS_KEEP_DAILY_PARTS, DUMPS_KEEP_WEEKLY_PARTS and
    # DUMPS_KEEP_MONTHLY_PARTS. If DUMPS_LOCAL_DIR is not specified or
    # is empty then all the dumps are created directly in a date-named
    # directory in DUMPS_ARCHIVE_DIR.

The configuration example (see also
[config.sh.example](bin/config.sh.example)).

    DUMPS_DBNAME_LIST='dbname1 dbname2'
    DUMPS_LOCAL_DIR=
    DUMPS_ARCHIVE_DIR='/storage/dumps'
    DUMPS_KEEP_DAILY_PARTS='3 days'
    DUMPS_KEEP_WEEKLY_PARTS='1 month'
    DUMPS_KEEP_MONTHLY_PARTS='1 year'

The script creates a dump of global objects (roles, tablespaces) to
the file `globals.sql` and compressed dump in a `custom` format for
each of the specified databases. All these files it puts into a
directory named for a current date as `YYYYMMDD`. If a local directory
is specified it creates it there and then `rsync` it to the archive
directory. It might be useful if you have a networking problems and
dumping through the network might lead to long locks or even process
stalls.

For days, weeks and months it keeps daily dumps, Monday dumps and the
first day of month dumps respectively for as long as you specify in
the according configuration parameters.

Just put it to `crontab`, adjust the config and it will do all the
work.
