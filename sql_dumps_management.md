# PgCookbook - a PostgreSQL documentation project

## SQL Dumps Management

One of the DBA's "must do" tasks is to perform and maintain SQL
backups. And one of the most frequent question is what is the best
practice of creating, archiving and cleaning obsolete backups. Of
course it depends on a particular business requirements and technical
environment, that might be quite tricky. Fortunately
[PgCookbook](README.md) has a flexible generic solution for this, that
is build around `pg_dump` and `pg_dumpall`. Meet
[manage_dumps.sh](bin/manage_dumps.sh).

Below is the documentation string.

    Makes compressed SQL dumps of every database in DUMPS_DBNAME_LIST
    and an SQL dump of globals to a date-named directory in
    DUMPS_LOCAL_DIR and then RSYNC this directory to
    DUMPS_ARCHIVE_DIR, removing outdated ones from DUMPS_ARCHIVE_DIR
    based on DUMPS_KEEP_DAILY_PARTS, DUMPS_KEEP_WEEKLY_PARTS and
    DUMPS_KEEP_MONTHLY_PARTS. If DUMPS_LOCAL_DIR is not specified or
    is empty then all the dumps are created directly in a date-named
    directory in DUMPS_ARCHIVE_DIR.

The configuration is in `config.sh` under the `bin` directory. The
specific settings are shown below. For all the settings see
[config.sh.example](bin/config.sh.example).

    DUMPS_DBNAME_LIST='dbname1 dbname2'
    DUMPS_LOCAL_DIR=
    DUMPS_ARCHIVE_DIR='/mnt/archive/dumps'
    DUMPS_KEEP_DAILY_PARTS='3 days'
    DUMPS_KEEP_WEEKLY_PARTS='1 month'
    DUMPS_KEEP_MONTHLY_PARTS='1 year'

Let's see how it works. First, the script dumps global objects (roles,
tablespaces) to the file `globals.sql`. Next, it creates a compressed
dump in the `custom` format for each of the specified databases. If no
local directory specified, it creates all these files in a directory
named for current date as `YYYYMMDD` inside of the archive
directory. If a local directory is specified, the script creates a
date-named directory with the dumps in the local one first, and then
`rsync`'s it to the archive one. The latter might be useful in the
case of network problems, when dumping directly to the network mount
point might lead to long locks or even process stalls.

For days, weeks and months it keeps daily dumps, Monday dumps and the
first day of month dumps respectively for as long as it is specified
in the configuration.

Just adjust the settings, put it in your `crontab`

    00 01 * * * bash pgcookbook/bin/manage_dumps.sh

and it will do all the hard work.
