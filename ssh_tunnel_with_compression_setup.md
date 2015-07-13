# PgCookbook - a PostgreSQL documentation project

## SSH-Tunnel with Compression Setup

Let's assume that we have two servers, `host1` and `host2`, with
PostgreSQL running on 5432 port. They exchange with large amounts of
data, but the connection between them is very slow and we constantly
experiencing long lags or even out of sync issues. Another issue is
that the servers might communicate via the Internet that is not safe
for our very valuable data.

Often, to work around these problems, an SSH-tunnel with compression
can be established between the servers and the traffic can be
redirected through it. It can boost the throughput up to several times
and protect the data from interception. The script
[ssh_tunnel.sh](bin/ssh_tunnel.sh) from our [PgCookbook](README.md)
will make the life easier by doing all the hard work for you.

The documentation string.

    Forwards localhost::TUNNEL_PORT on TUNNEL_HOST to
    localhost::TUNNEL_HOST_PORT on the local side over SSH tunneling
    with compression using TUNNEL_COMP_LEVEL. It assumes that SSH
    without password is configured between servers. The script was
    made for running as a cron job and exits normally if another
    instance is running with the same TUNNEL_LOCK_FILE. In case of
    network failures it attempts to re-establish connection after
    TUNNEL_RETRY_DELAY.

The configuration is expected to be in `config.sh` under the `bin`
directory. The script specific settings are shown below. For all the
settings see [config.sh.example](bin/config.sh.example).

    test -z "$TUNNEL_PORT" && TUNNEL_PORT=2345
    test -z "$TUNNEL_HOST_PORT" && TUNNEL_HOST_PORT=5432
    test -z "$TUNNEL_HOST" && TUNNEL_HOST='host2'
    TUNNEL_COMP_LEVEL=2
    TUNNEL_RETRY_DELAY=60
    test -z "$TUNNEL_LOCK" && \
        TUNNEL_LOCK="$TUNNEL_PORT-$TUNNEL_HOST_PORT-$TUNNEL_HOST"
    test -z "$TUNNEL_LOCK_FILE" && \
        TUNNEL_LOCK_FILE="/tmp/ssh_tunnel.$TUNNEL_LOCK"

Note that the script assumes that you have already
[setup SSH without password](ssh_without_password_setup.md) between
servers. If so then just run it on `host1` or put it in cron

    * * * * * bash pgcookbook/bin/ssh_tunnel.sh

and you will be able to communicate with the port 5432 on `host1` via
the port 2345 on `host2` with transparent compression by secured line.

Note, that you might probably want to experiment with
`TUNNEL_COMP_LEVEL` to find out which value is the most effective for
you. Do not set it too high because you might face CPU limits, usually
1 or 2 is enough for the most of cases.
