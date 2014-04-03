# PgCookbook - a PostgreSQL documentation project

## Slony1 Replication Setup

Suppose we have two servers, `host1` (192.168.0.1) and `host2`
(192.168.0.2), with PostgreSQL instances listening ports 5432. The
`host1`'s instance houses a `billing` database. The goal is to setup a
replication of this database from `host1` to `host2` using Slony1.

First install Slony1 binaries and create a `slony` user it the
database on `host1` that will be used for replication purposes. We
will create it as a superuser to simplify things. If you need it to be
more secure [read here][1]. Also turn off `statement_timeout` for the
user as it is supposed to perform long `COPY` operations.

    CREATE USER slony SUPERUSER;
    ALTER USER slony SET statement_timeout TO 0;

This instruction assumes that you allow trusted connections locally
and between both hosts in `pg_hba.conf` for this user.

    # TYPE  DATABASE        USER       CIDR-ADDRESS            METHOD
    # Slony1 replication
    local   billing         slony                              trust
    host    billing         slony      192.168.0.1/32          trust
    host    billing         slony      192.168.0.2/32          trust

Now we need to copy the `billing` schema and globals (roles and
tablespaces) to `host2`. Log in with user `postgres` on `host1`.

    pg_dumpall -g | psql -h host2
    pg_dump -s -N _slony -C billing | psql -h host2

Then log in as `root` and go to `/etc/slony1`. Create a directory
named `billing` and `cd` there. Put there [slon.conf](slony/slon.conf)
and edit the `conn_info` parameter in this file.

Do the same on `host2`.

Restart Slony1 on both servers as it is shown below. First stop it if
it is running.

    /etc/init.d/slony1 stop

Make sure that all of its processes are stopped on both servers. Check
it with `ps`. It is necessary to do because in some cases the service
does stops with a delay.

    ps aux | grep slon

And finally start the services on both servers.

    /etc/init.d/slony1 start

Since now we need to begin monitoring log files on both servers. Check
that everything is okay there. There should not be any errors or
suspicious activity, except the ones about the not existing `_slony`
schema.

    tail -f /var/log/slony1/slon-billing.log

On `host1` log in back with `postgres` user and create a
`~/slony/billing` directory to keep customized Slony1 scripts and `cd`
into it.

    mkdir -p ~/slony/billing
    cd ~/slony/billing

Copy and customize
[config_cluster.slonik](slony/config_cluster.slonik) modifying
connection settings appropriately.

Next we need to initialize our replication cluster and create the
replication set. Copy `.slonik` files shown below or just use the
repository work directory path if you checked it out.

Skim the content of [init_cluster.slonik](slony/init_cluster.slonik)
and [create_set.slonik](slony/create_set.slonik) and apply them.

    slonik init_cluster.slonik
    slonik create_set.slonik

Ensure that all the tables that are supposed to be replicated have
unique or primary keys with
[get_tables_without_pk_and_uniqs.sql](sql/get_tables_without_pk_and_uniqs.sql).

    psql -d billing -f get_tables_without_pk_and_uniqs.sql

If some does not have you need to create the them. It is Slony1
requirements.

After that we need to add all the tables and sequences to the
replication. Copy and customize this sample file
[populate_set.slonik](slony/populate_set.slonik).

To automate the routine use
[generate_full_slonik_set.sql](sql/generate_full_slonik_set.sql).

Apply additional filtration (with `grep`, etc), eg. if you need some
particular schema.

    psql -At -d billing -f generate_full_slonik_set.sql | \
        grep 'someschema\.' >> populate_set.slonik

If you need to add missing tables and sequences to an existing
replication use
[generate_incremental_slonik_set.sql](sql/generate_incremental_slonik_set.sql)
above.

Do not forget to review the resulting file and apply it.

    slonik populate_set.slonik

If you have found out that you do not need to replicate some tables or
sequences copy and customize the
[clear_set.slonik](slony/clear_set.slonik) sample file. To automate
the routine use
[generate_slonik_set_to_drop.sql](sql/generate_slonik_set_to_drop.sql).

Check whether all the necessary tables are added to the replication by
[get_not_in_slony_tables_and_sequences.sql](sql/get_not_in_slony_tables_and_sequences.sql).

    psql -d billing -f get_not_in_slony_tables_and_sequences.sql

Now initialize the replication on `host2` by creating a slave node
with [store_node.slonik](slony/store_node.slonik). Skim the file
before running the command.

    slonik store_node.slonik

Set the replication's paths with
[store_path.slonik](slony/store_path.slonik) checking the file
preliminary as well.

    slonik store_path.slonik

And finally subscribe the created set, sync it and start replicating
with [subscribe_set.slonik](slony/subscribe_set.slonik).

    slonik subscribe_set.slonik

At this moment carefully watch the logs. If you mixed up with master
and slave you need to find it out as fast as possible to stop the
replication as it could damage the data.

[1]: http://slony.info/documentation/2.1/security.html#SUPERUSER
