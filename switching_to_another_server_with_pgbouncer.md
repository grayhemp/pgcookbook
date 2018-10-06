# PgCookbook - a PostgreSQL documentation project

## Switching to Another Server with PgBouncer

Does not matter what replication tools you use, it is always important
to switch servers as gently as possible and with minimum downtime.

Imagine we have two database servers `host1` (192.168.0.1) and `host2`
(192.168.0.2). A replication (streaming, Slony1, longiste, bucardo,
etc.) is set up between these machines. `host1` is a origin server and
`host2` is a replica. All the clients are connecting to the databases
via pgbouncer instances working on both servers. Initially, each
instance serving databases on a local machine.

The goal is to switch the origin role to `host2`.

The idea is to redirect all the queries from `host1` to `host2` by
pgbouncer during the process of switching. The benefit of this
solution is that the process will be transparent (or almost
transparent) for clients and wont involve another parties to do such
things such as application DSN, IP or DNS reconfiguration. They might
do it later themselves without rush if they will need it at all.

First, we need to prepare `pgbouncer.ini` on `host1` so that it will
point to the `host2`. No restart or reload is needed at this moment.

    [databases]
    ;* = host=127.0.0.1
    * = host=192.168.0.2

Note, if you are going to make your clients to connect to `host2`
directly later, then make sure that both `pgbouncer.ini` and
`userlist.txt` on `host2` are identical to `host1` ones. 

Also make sure that there are no connections to the origin (`host1`)
bypassing pgbouncer.

    SELECT client_addr, usename, datname, application_name, current_query 
    FROM pg_stat_activity
    WHERE client_addr NOT IN ('127.0.0.1') OR client_addr IS NULL;

Keep in mind long transactions. If you have something like this in
cron or anywhere else, turn it off on the time of the promotion. Check
if there are any of them on the origin.

    SELECT now() - xact_start, procpid, current_query
    FROM pg_stat_activity 
    ORDER BY 1 DESC NULLS LAST LIMIT 5;

Stop them if it is possible or wait for them to finish.

Make everything that connects directly to PostgreSQL to go via
pgbouncer if the pooling mode allows it, otherwise, just turn that
off temporarily, probably by commenting out necessary entries in
`pg_hba.conf` and reloading PostgreSQL.

At this step you need to decide if it is necessary to start a service
window or not. From the point of view of the technical side, it
depends on the replication system you use. If it can promote your
replica to origin fast (in several seconds) then in many cases you do
not need the service window, otherwise, you do. If you have thousands
client sessions per second, then most probably you need it. If your
pgbouncer is in `session` pooling mode, then you need it either.

Prepare your replication tools to speed up the promotion process.

For londiste you can prepare a set of commands to unregister all the
tables and sequences.

For streaming replication run the `CHECKPOINT` command a couple of
times on the replica one after another to reduce the checkpoint time
during the promotion. The time of the second run will give a hint of
the approximate pause.

For Slony1 write a script to do the promotion automatically.

Now the main and the most important part of the action. Take a deep
breath and try to do all the next steps without delays.

Start the service window if it is needed.

If your pgbouncer version is `<1.5.3` and your `pgbouncer.ini`
contains so called autodb entries (like `* =`), then you will need to
restart the pgbouncer on the origin (`host1`) to redirect clients.

    /etc/init.d/pgbouncer restart

And then promote the replica (`host2`) as a new origin with your
replication tool.

Otherwise, if pgbouncer `>=1.5.3`, you can do it a more gently and
transparent for clients way, so they will not notice anything except
maybe a short delay.

    /etc/init.d/pgbouncer pause
    /etc/init.d/pgbouncer reload

If your pgbouncer package does not provide a `pause` and/or `reload`
command in the init script, you can do it via console, by connecting
to pgbouncer with psql and executing `PAUSE; RELOAD;`.

    psql -p 6432 -c 'PAUSE; RELOAD;'

Always have the query below ready in case if something long running
unexpectedly appears to stop it, because it might hang the promotion
process.

    SELECT pg_terminate_backend(pid) FROM pg_stat_activity
    WHERE now() - xact_start > '5 seconds';

Then promote the replica (`host2`) as a origin and remove the pause from
pgbouncer.

    /etc/init.d/pgbouncer continue

The same as with `PAUSE; RELOAD;` you can run `RESUME;` via console
instead of the command above if it is not supported by the package.

    psql -p 6432 -c 'RESUME;'

Now clients queries are redirected to the new origin (`host2`).

And then finally stop the `postgres` instance on the old origin
(`host1`).

    /etc/init.d/postgresql stop

Check the pgbouncer and postgres logs, make sure that everything is
fine and there are no errors.

Now you can breathe out.

Note, that if you want to turn the `host1` off you can forward all the
traffic from clients to `host2` with DNS or IP aliasing. Another
important moment is the necessity of pgbouncer restart when changing
IP of the new origin.
