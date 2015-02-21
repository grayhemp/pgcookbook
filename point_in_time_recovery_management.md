# PgCookbook - a PostgreSQL documentation project

## Point-in-Time Recovery Management

PITR (Point-in-Time Recovery) backup is one of the vital parts of a
PostgreSQL environment. It is involves two kinds of processes - base
backup of the database cluster and WAL archiving.

The most common way of configuring it can be
described with these steps:

1. 
2. 

    Creates an archived base backup in a current date named directory
    in PITR_ARCHIVE_DIR, removes outdated base backup directories, in
    accordance with PITR_KEEP_DAYS, from PITR_ARCHIVE_DIR, and cleans
    WAL files, that are older than the oldest kept base backup, from
    PITR_WAL_ARCHIVE_DIR. If PITR_LOCAL_DIR is specified, it creates
    the base backup in this directory first and then RSYNC it to
    PITR_ARCHIVE_DIR. If PITR_WAL is set to true it starts a process
    of streaming WAL to PITR_WAL_ARCHIVE_DIR using PGRECEIVEXLOG. The
    streaming process is made for running as a cron job and exits
    normally if another instance is running with the same
    PITR_WAL_RECEIVER_LOCK_FILE.



    test -z "$PITR_WAL" && PITR_WAL=false
    PITR_LOCAL_DIR=
    PITR_ARCHIVE_DIR='/mnt/archive/basebackups'
    PITR_WAL_ARCHIVE_DIR='/mnt/archive/wal'
    test -z "$PITR_WAL_RECEIVER_LOCK_FILE" && \
        PITR_WAL_RECEIVER_LOCK_FILE='/tmp/wal_receiver.'$(
            echo $PITR_WAL_ARCHIVE_DIR | sed 's/\//_/g'
        )"-$HOST-$PORT-$USER"
    PITR_KEEP_BACKUPS=2
