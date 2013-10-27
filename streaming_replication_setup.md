# PgCookbook - a PostgreSQL documentation project

## Streaming Replication Setup

Suppose we have two instances running on two servers db1 (192.168.0.1)
and db2 (192.168.0.2), each serving the port 5432. We need to setup a
streaming replication from db1 (primary) to db2 (standby).

Before starting preparation of the database servers check the
connection and the bandwidth between servers. It must be enough to
transmit your new WAL files. If the situation is not very good it is
recommended to forward the port from master to replica using
ssh-tunneling with compression enabled. In future versions of
PostgreSQL the compression will be implemented in the DBMS itself.

Start the following sniplet via the `screen` utility on db1. It will
forward the `localhost:5432` on db1 to the `localhost:2345` on db2
with compression.

    while [ ! -f /tmp/stop ]; do
        ssh -C -o ExitOnForwardFailure=yes -R 2345:localhost:5432 \
	    db2 "while nc -zv localhost 2345; do sleep 5; done";
        sleep 5;
    done

Then we need to prepare db1.

Edit the `postgresql.conf`.

Set the `wal_keep_segments` configuration parameter. The server keeps
the extra number of WAL segments to allow the standby collect them
before they are recycled. It is advised to set it to the double number
of WAL files that are rotating during the time of a maximum expected
lag. It is usually up to twice higher than `checkpoint_segments`
depending on the load.

    wal_keep_segments = 256

After the replication is set up configure your notification system to
inform you when the lag is close to the maximal expected value so it
will be a half way before the standby falls behind to much.

Set `max_wal_senders`, maximum number of concurrent connections from
standby servers. Although we have only one standby server it could be
supposed that there will be more of them. So let us set it to 3 to
avoid redundant restarts in future.

    max_wal_senders = 3

And set `wal_level` to enable hot standby (read-only queries on the
replica).

    wal_level = hot_standby

Do not forget to set `listen_addreses` so the standby server could
establish connections.

    listen_addresses = 'localhost,192.168.0.1'

Now create a superuser to perform the replication with the system user
`postgres`.

    createuser -P -s -l replica
    Enter password for new role: 
    Enter it again: 

And allow replication connections from standby servers for the user in
`pg_hba.conf` (replication below is a pseudo database).

    # TYPE  DATABASE        USER        CIDR-ADDRESS            METHOD
    # Replication connections
    host    replication     replica     192.168.0.2/32           md5

If the ssh-tunneling is used then the IP address here will be
`127.0.0.1/32`.

Okay, everything is ready to restart the primary server now. Usually
it is performed with `root`.

    /etc/init.d/postgresql restart

Now it is time to configure db2.

Edit the `postgresql.conf`.

Make the standby able to receive read-only queries. 

    hot_standby = on

Create a `recovery.conf` file in the data directory and fill it with
the configuration below.

    standby_mode = 'on'
    primary_conninfo = 'host=192.168.0.1 port=5432 user=replica password=somepassword'
    trigger_file = '/db/data/failover'

By this we turned standby mode on, specified a connection string to
the primary server and specified a path to the trigger file which
presence ends the recovery thereby making a failover.

In case of the ssh-tunneling specify host as `127.0.0.1` and port as
`2345`.

Note, if you are planning to run long queries on the standby and it is
possible that the data they use can be changed during their execution
on the master then they can be cancelled automatically with errors
like this.

    ERROR:  canceling statement due to conflict with recovery
    DETAIL:  User query might have needed to see row versions that must be removed.

This happens because PostgreSQL in the hot standby mode has a timeout
for queries conflicting with about-to-be-applied WAL entries.

To avoid this you need to adjust a special parameter in
`postgresql.conf` that states the maximum possible delay of data
recovery before such queries are canceled.

    max_standby_streaming_delay = 5min

Now we need to perform the initial copy of our data. Note that it must
be done as quickly as possible to avoid standby synchronization
failure.

Do not forget to stop the standby server.

    /etc/init.d/postgresql stop

Note, that the mount points of the tablespaces on standby must be the
same as on the primary server.

Okay, now we need to make a base backup and have two ways of doing it
depending on the version installed.

If it is `>=9.1` then things are much simpler.

On the standby server make a backup of all the configuration files and
remove the data directory and all the tablespaces mount points
content.

    cp /db/data/*.conf ~/tmp
    rm -rf /db/data

Run the `pg_basebackup` tool specifiying the data directory.

    pg_basebackup -v -P -c fast -h db1 -U replica -D /db/data

Restore the configuration from the backup.

    cp ~/tmp/*.conf /db/data/

Important note! In the `pg_basebackup` data transfer compression is
not implemented yet, it is expected to appear in future versions. So
if you have a bad bandwidth between your servers use the old school
base backup method as it is described below. Alternatively you can use
the ssh-tunneling with compression by specifying its port.

Now about `9.0`. It requires a little bit more work but allows you to
get under the hood.

Tell the primary server that we are starting a backup.

    psql -U replica postgres -c "select pg_start_backup('copy', true);"
     pg_start_backup 
    -----------------
     0/3000020
    (1 row)

Do rsync the data from db1 to db2 (see also
[ssh_without_password_setup.md][SSH Without Password Setup]).

    rsync -av --delete -z --progress --compress-level=1 \
        --exclude pg_xlog --exclude *.conf --exclude postgresql.pid \
        /db/data db2:/db/

Repeat this for every tablespace of the database.

Tell the primary server to stop the backup.

    psql -U replica -d postgres -c "select pg_stop_backup();"
    ----------------
     0/30000D8
    (1 row)

Now everything is ready to start the standby on db2.

    /etc/init.d/postgresql start

If everything is okay you will see this in the PostgreSQL logs on the
standby.

    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-2]:LOG:  entering standby mode
    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-3]:LOG:  redo starts at 0/3000020
    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-4]:LOG:  consistent recovery state reached at 0/4000000
    2011-04-05 11:10:21 MSD @ 69969 [4d9ac05c.11151-1]:LOG:  database system is ready to accept read only connections
    2011-04-05 11:10:21 MSD @ 69974 [4d9ac05d.11156-1]:LOG:  streaming replication successfully connected to primary

And this in the primary logs.

    2011-04-05 11:10:21 MSD [unknown]@[unknown] 57305 [4d9ac05d.dfd9-1]:LOG:  connection received: host=192.168.0.2 port=10562
    2011-04-05 11:10:21 MSD replica@[unknown] 57305 [4d9ac05d.dfd9-2]:LOG:  replication connection authorized: user=replica host=192.168.0.2 port=10562

You can additionally test the replication directly, just like it is
shown below.

On db1 create a table.

    psql somedb -c 'CREATE TABLE t (t text);'
    CREATE TABLE

And check it on db2.

    psql somedb -c '\dt t'
            List of relations
     Schema | Name | Type  |  Owner   
    --------+------+-------+----------
     public | t    | table | postgres
    (1 rows)

Or you can also check replication status with `pg_stat_replication`
view if you are on `>=9.1`.

    psql somedb -x -c 'SELECT * FROM pg_stat_replication;'
