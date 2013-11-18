# PgCookbook - a PostgreSQL documentation project

## Switching To Another Server With PgBouncer

Does not matter what replication tools you use it is always important
to switch servers as gently as possible and with minimum downtime.

Okay, imagine we have two database servers `host1` (192.168.0.1) and
`host2` (192.168.0.2). Also a replication process (no matter which
one) is working between these machines, `host1` is a master and
`host2` is a slave. All the clients are communicating to the databases
via pgbouncer instances working on both servers. Initially each
instance serving databases on a local machine.

The goal is to switch the master role to `host2`.

We will need to redirect all the queries from `host1` to `host2` by
`pgbouncer` in the process of switching. So first of all we need to
adjust the `pgbouncer` configuration according to it on `host1`
without restarting it.

    [databases]
    ;* = host=127.0.0.1
    * = host=192.168.0.2

Then ensure that `pgbouncer.ini` and `userlist.txt` are identical on
both servers. Also ensure that there are no connections to the master
(`host1`) bypassing the `pgbouncer`.

    SELECT client_addr, usename, datname, application_name, current_query 
    FROM pg_stat_activity
    WHERE client_addr NOT IN ('127.0.0.1') OR client_addr IS NULL;

Close the ability to connect directly in `pg_hba.conf`.

At this step you need to decide if it is needed to start a service
window or not. It depends on the replication system you use. If it
allows to promote your slave to master fast (in several seconds) then
in many cases you do not need it, otherwise you do. Prepare your
replication tools so the promotion to be performed faster.

For `londiste` you can prepare a set of commands to unregister all the
tables and sequences.

For streaming replication run the `CHECKPOINT` command twice on slave
one after another to reduce the checkpoint time during the
promotion. The time of the second run will give a hint of the
approximate downtime.

For Slony1 write a script to do the promotion automatically.

Preliminary check if there are some long queries working on the
master.

    SELECT now() - xact_start, procpid, current_query
    FROM pg_stat_activity 
    ORDER BY 1 DESC NULLS LAST LIMIT 5;

Stop them if it is possible or wait for them to finish.

Now the main and the most important part of the action. Take a deep
breath and try to do all the next steps without delays.

Start the service window if it is needed.

If you `pgbouncer` version is `<1.5.3` and your `pgboincer.ini`
contains `autodb` entries (like `* =`), then you will need to restart
the `pgbouncer` on the master (`host1`) to redirect clients.

    /etc/init.d/pgbouncer restart

And then promote the slave (`host2`) as a new master with your
replication tool.

Otherwise, if pgbouncer `>=1.5.3`, you can do it more gently way and
transparent for clients so they will not notice anything except maybe
a small delay.

    /etc/init.d/pgbouncer pause
    /etc/init.d/pgbouncer reload

Then promote the slave (`host2`) as a master and remove the pause from
`pgbouncer`.

    /etc/init.d/pgbouncer continue

Now clients queries are redirected to the new master (`host2`).

And then finally stop the `postgres` instance on the old master (`host1`).

    /etc/init.d/postgresql stop

Check the `pgbouncer` and `postgres` logs, make sure that everything
is okay and there are no errors.

Now you can breathe out.

Note, that if you want to turn the `host1` off you can forward all the
traffic from clients to `host2` with DNS or IP aliasing. Another
important moment is the necessity of pgbouncer restart when changing
IP of the new master.
