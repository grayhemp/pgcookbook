# PgCookbook - a PostgreSQL documentation project

## SSH-Tunnel with Compression Setup

Let us assume that we have two servers, `host1` (192.168.0.1) and
`host2` (192.168.0.2), with PostgreSQL running on 5432 port. They
exchange with a large amounts of data, but the connection between them
is very slow and we constantly experiencing huge lags or even out of
sync issues.

Often to work around this problem an SSH-tunnel with compression can
be established between the servers and the traffic can be redirected
through it. It might boost the data throughput up to several
times. The script [ssh_tunnel.sh](bin/ssh_tunnel.sh) from our
[PgCookbook](README.md) will ease our lives by doing all the hard work
itself.

The documentation string.

    Forwards localhost::TUNNEL_PORT on TUNNEL_HOST to
    localhost::TUNNEL_HOST_PORT on the local side over SSH tunneling
    with compression using TUNNEL_COMP_LEVEL. It assumes that SSH
    without password is configured between servers. The script was
    made for running as a cron job and exits normally if another
    instance is running with the same TUNNEL_LOCK_FILE. In case of
    network failures it attempts to re-establish connection after
    TUNNEL_RETRY_DELAY.

The configuration is in `config.sh` under the `/bin` directory. The
specific settings are below. For all the settings see
[config.sh.example](bin/config.sh.example).

    test -z $TUNNEL_PORT && TUNNEL_PORT=2345
    test -z $TUNNEL_HOST_PORT && TUNNEL_HOST_PORT=5432
    test -z $TUNNEL_HOST && TUNNEL_HOST='host2'
    TUNNEL_COMP_LEVEL=2
    TUNNEL_RETRY_DELAY=60
    test -z $TUNNEL_LOCK_FILE && \
        TUNNEL_LOCK_FILE="/tmp/ssh_tunnel.$TUNNEL_HOST.$TUNNEL_HOST_PORT"

Note that the script assumes that you have already [setup SSH without
password](ssh_without_password_setup.md) between servers. Then just
run the script on `host1` or put it in cron.

    bash ssh_tunnel.sh

And you will be able to communicate to the port 5432 on `host1` via
the port 2345 on `host2` with transparent compression.
