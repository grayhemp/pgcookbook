# PgCookbook - a PostgreSQL documentation project

## SSH-Tunnel with Compression Setup

Let us assume we have two servers `host1` (192.168.0.1) and `host2`
(192.168.0.2) on with PostgreSQL on ports 5432. They exchange with
large amounts of data, but the connection between them is very slow
and we constantly experiencing huge lags or even out of sync cases.

To partially this problem we might establish an SSH-tunnel with
compression between servers and direct our traffic though this. It
might boost the data throughput up to several times. The script
[ssh_tunnel.sh](bin/ssh_tunnel.sh) will ease our lives by doing all
the hard work itself.

From its description.

    # Forwards localhost::TUNNEL_PORT on TUNNEL_HOST to
    # localhost::TUNNEL_HOST_PORT on the local side over SSH tunneling
    # with compression using TUNNEL_COMP_LEVEL. It assumes that SSH
    # without password is configured between servers. The script was
    # made for running as a cron job and exits normally if another
    # instance is running with the same TUNNEL_LOCK_FILE. In case of
    # network failures it attempts to re-establish connection after
    # TUNNEL_RETRY_DELAY.

The example configuration (see also
[config.sh.example](bin/config.sh.example)).

    TUNNEL_PORT=2345
    TUNNEL_HOST_PORT=5432
    TUNNEL_HOST='db2'
    TUNNEL_COMP_LEVEL=2
    TUNNEL_RETRY_DELAY=60
    TUNNEL_LOCK_FILE='/tmp/ssh_tunnel.lock'

The script assumes that you have already [setup SSH without
password](ssh_without_password_setup.md). Just run the script on
`host1`.

    bash ssh_tunnel.sh

And you will be able to communicate with port 5432 on `host1` via 2345
on `host2` with transparent compression.
