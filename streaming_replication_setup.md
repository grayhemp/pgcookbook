# PgCookbook - a PostgreSQL documentation project

## Streaming Replication Setup

Let us suppose we have two instances running on two servers `host1`
(192.168.0.1) and `host2` (192.168.0.2), each serving the
port 5432. We need to setup a streaming replication from `host1`
(primary) to `host2` (standby).

Before starting preparations of the database servers, check the
bandwidth between them. It must be enough to transmit your WAL
stream. If the situation is not very good it is recommended to forward
the port from origin to replica using [SSH-tunneling with
compression](ssh_tunnel_with_compression_setup.md). In the future
versions of PostgreSQL the compression will probably be built-in.

First, we need to prepare `host1`.

Edit `postgresql.conf`.

Set the `wal_keep_segments` configuration parameter. The server keeps
an extra number of WAL files (segments) to allow standbys to collect
them before these files are recycled. It is advised to set it to the
double number of WAL files that can be rotated during the time of a
maximum expected lag. If you don't know your maximum expected lag than
a good starting point will be to set it twice higher than your
`checkpoint_segments` but not less than 64.

    wal_keep_segments = 256

Set `max_wal_senders`, maximum number of concurrent connections from
standby servers. Although we have only one standby server right now,
we can assume that there might more of them in future. So let us
set it to 3 to avoid redundant restarts in future.

    max_wal_senders = 3

And set `wal_level` to enable hot standby (read-only queries on the
replica).

    wal_level = hot_standby

Do not forget to set `listen_addreses` so the standby server could
connect.

    listen_addresses = 'localhost,192.168.0.1'

Now create a superuser to perform the replication with the system user
`postgres`.

    createuser -P -s -l replica
    Enter password for new role: 
    Enter it again: 

And allow replication connections from standbys for the user in
`pg_hba.conf` (the `replication` below is a pseudo database).

    # TYPE  DATABASE        USER        CIDR-ADDRESS            METHOD
    # Replication connections
    host    replication     replica     192.168.0.2/32           md5

If an SSH-tunneling is used then the IP address here will be
`127.0.0.1/32`.

Okay, everything is ready to restart the primary server now. Usually
it is performed with `root`. Note, you need `restart` here if
`max_wal_senders` or `wal_level` was changed only, otherwise `reload`
is enough.


    /etc/init.d/postgresql restart

Now it is time to configure `host2`.

Edit `postgresql.conf`.

Make the standby able to receive read-only queries. 

    hot_standby = on

Create a `recovery.conf` file in the data directory and put the
configuration like shown below in it.

    standby_mode = 'on'
    primary_conninfo = 'host=192.168.0.1 port=5432 user=replica password=somepassword'
    trigger_file = '/path/to/data/dir/failover'

By this we turned standby mode on, specified a connection string to
point to the primary server, and specified a path to the trigger file
which presence will be a signal for PostgreSQL to finish the recovery
and to promote the replica to a origin. In case of the ssh-tunneling
specify the host as `127.0.0.1` and the port as `2345`.

Note, if you are planning to run long queries on the standby and it is
possible that the data they use can be changed during their execution
on the origin then they can be canceled automatically with errors like
below.

    ERROR:  canceling statement due to conflict with recovery
    DETAIL:  User query might have needed to see row versions that must be removed.

It happens because PostgreSQL in the hot standby mode has a timeout
for queries conflicting with about-to-be-applied WAL entries.

To avoid this you need to adjust a special parameter in
`postgresql.conf` that sets the maximum possible delay of data
recovery before such queries are canceled.

    max_standby_streaming_delay = 5min

Also, to avoid query cancels caused by VACUUM's record cleanup on
origin, let us make our replica to send a feedback about currently
executing queries. It is available for versions `>=9.1`.

    hot_standby_feedback = on

Now, we need to perform the initial copy of our data. Note, that it
must be done as quickly as possible to avoid standby synchronization
failure.

Do not forget to stop the standby server.

    /etc/init.d/postgresql stop

Also note, that the mount points of the tablespaces on the standby
must be the same as on the primary server. To check it run `\db+` in
psql on the origin.

Okay, it is time to do a base backup. We have two ways of doing it
depending on the version installed.

If it is `>=9.1` then things are much simpler.

On the standby server make a backup of all the configuration files if
they are in the data directory, and remove the data directory
itself. Also remove all the tablespace directories if any.

    cp /path/to/db/data/dir/*.conf ~/tmp
    rm -rf /db/data

Run the `pg_basebackup` tool specifiying the data directory.

    pg_basebackup -v -P -c fast -h host1 -U replica -D /db/data

Restore the configuration from the backup if it is needed.

    cp ~/tmp/*.conf /db/data/

Important note! In `pg_basebackup` no data transfer compression is
implemented. Probably we will get it in the future versions. So if you
have a slow bandwidth between your servers use the old school base
backup method as it is described below. Alternatively you can use the
SSH-tunneling with compression by specifying its port to
`pg_basebackup`.

Now for `9.0`. It requires a little bit more work but allows you to
get under the hood.

Tell the primary server that we are starting a backup.

    psql -U replica postgres -c "select pg_start_backup('copy', true);"
     pg_start_backup 
    -----------------
     0/3000020
    (1 row)

Do `rsync` the data from `host1` to `host2`. You will probably want to
setup [SSH without password](ssh_without_password_setup.md) here
first.

    rsync -av --delete -z --progress --compress-level=1 \
        --exclude pg_xlog --exclude *.conf --exclude postgresql.pid \
        /db/data/ host2:/db/data

Repeat this for every tablespace of the database. Sometimes it is
worth to run all the `rsync`'s simultaneously, mostly if you have a
good bandwidth and separate storage devices for your tablespaces.

And tell the primary server to stop the backup.

    psql -U replica -d postgres -c "select pg_stop_backup();"
    ----------------
     0/30000D8
    (1 row)

Now everything is ready to start the standby on `host2`.

    /etc/init.d/postgresql start

If everything is okay you will see this in the PostgreSQL logs on the
replica.

    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-2]:LOG:  entering standby mode
    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-3]:LOG:  redo starts at 0/3000020
    2011-04-05 11:10:21 MSD @ 69971 [4d9ac05d.11153-4]:LOG:  consistent recovery state reached at 0/4000000
    2011-04-05 11:10:21 MSD @ 69969 [4d9ac05c.11151-1]:LOG:  database system is ready to accept read only connections
    2011-04-05 11:10:21 MSD @ 69974 [4d9ac05d.11156-1]:LOG:  streaming replication successfully connected to primary

And this will appear in the origin logs.

    2011-04-05 11:10:21 MSD [unknown]@[unknown] 57305 [4d9ac05d.dfd9-1]:LOG:  connection received: host=192.168.0.2 port=10562
    2011-04-05 11:10:21 MSD replica@[unknown] 57305 [4d9ac05d.dfd9-2]:LOG:  replication connection authorized: user=replica host=192.168.0.2 port=10562

You can additionally test the replication directly, just like it is
shown below.

On `host1` create a table.

    psql somedb -c 'CREATE TABLE t (t text);'
    CREATE TABLE

And check it on `host2`.

    psql somedb -c '\dt t'
            List of relations
     Schema | Name | Type  |  Owner   
    --------+------+-------+----------
     public | t    | table | postgres
    (1 rows)

Or just check the replication status with `pg_stat_replication` view
if you are on `>=9.1`.

    psql somedb -x -c 'SELECT * FROM pg_stat_replication;'
