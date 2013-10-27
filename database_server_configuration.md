# PgCookbook - a PostgreSQL documentation project

## Database Server Configuration

This text describes a checklist you need to follow when configuring a
new database server.

Check if the server is available by SSH and that necessary permissions
are granted. Depending on the situation you might need to `sudo` as
`postgres` or `root` user to control PostgreSQL and assisting
software, like replication tools, connection poolers, system utilities
and to manage configuration.

    sudo -l

If you are migrating a database to the server or setting up a hot
standby ensure that all the required mount points for tablespaces are
created. Use `\db+` in `psql` to check tablespaces and their
locations.

Ensure that the required version of PotsgreSQL is installed. If it is
not, then install the packages and initialize a cluster. Also check
and install all the needed satellite software, like replication
systems and connection poolers.

Now update `sysctl.conf`.

To not reboot the server, these settings can be set like it is shown
below. You'll need `sudo` to do this.

    sysctl -w some.parameter=some_value

Or just like this, after `sysctl.conf` will be completed, to not do it
one by one.

    sysctl -p /etc/sysctl.conf

If you are on `>=9.3` you not longer need the next step. Set the
`SHMMAX` and `SHMALL` kernel settings accordingly to the shared memory
amount assumed to be used.

Let us assume that we want to set shared buffers to 25% of RAM. Note
that shared buffers should be set slightly less than
`SHMMAX/SHMALL`. So let us set `SHMMAX/SHMALL` to 30% of RAM.

Calculate them like this. If you use FreeBSD use `sysctl -n
hw.availpages` instead of `getconf _PHYS_PAGES`.

    _SHMALL=$(expr $(getconf _PHYS_PAGES) \* 30 / 100)
    _SHMMAX=$(expr $(getconf PAGE_SIZE) \* $_SHMALL)

For FreeBSD use `kern.ipc.*` instead of `kernel.*`.

    kernel.shmall = 179085
    kernel.shmmax = 733532160

On FreeBSD add `kern.ipc.semmap` to these settings too.

    kern.ipc.semmap=256

Turn off swapping if you need it. Note that it is not recommended to
do for low RAM servers mostly, if they are not dedicated for
PostgreSQL as swapping may free some memory by moving some
initialization data to swap or it might provide hints about a lack of
memory.

    vm.swappiness = 0

For FreeBSD like this.

    vm.swap_enabled=0

If swap is not disabled on FreeBSD the following makes shared pages
non-swappable that is highly recommended for databases.

    kern.ipc.shm_use_phys=1

Maximum number of file-handles for Linux. It must be high for active
servers.

    fs.file-max = 65535

And for FreeBSD.

    kern.maxfiles=65535
    kern.maxfilesperproc=65535

`pdflush` tuning to prevent lag spikes for old Linux kernels.

    vm.dirty_ratio = 10
    vm.dirty_background_ratio = 1
    vm.dirty_expire_centisecs = 499

`pdflush` tuning to prevent lag spikes for new Linux kernels. The
recommended estimation is 64MB and 50% of the controller cache size
accordingly if the cache size is known. Otherwise 8MB and 64MB. Look
through `dmesg` for `scsi` (hardware RAID) or `md` (software RAID) to
determine what controller is installed.

    vm.dirty_background_bytes = 67108864
    vm.dirty_bytes = 536870912

On Linux with many processes (eg. client connections) increase this
setting to prevent the scheduler breakdown.

    kernel.sched_migration_cost = 5000000

It must be turned off on server Linux systems to provide more CPU to
PostgreSQL.

    kernel.sched_autogroup_enabled = 0

Setup `hugepages` for Linux. Do not forget to replace `110` with your
`postgres` group in `vm.hugetlb_shm_group`.

    vm.hugetlb_shm_group = 110
    vm.hugepages_treat_as_movable = 0
    vm.nr_overcommit_hugepages = 512

The Huge Page Size is 2048kB. So for example for 16GB shared buffers
the number of them is 8192.

    vm.nr_hugepages = 8192

On old Linux kernels, that does not support
`vm.nr_overcommit_hugepages` append additional 512 to the
`vm.nr_hugepages number`.

To make PostgreSQL use `hugepages` download and make the library as
described on [its page][1] and add it to the environment for the
postgres user (the environment file is in `/etc/postgresql/` or
`/etc/sysconfig/pgsql/` or `.bash_profile` in `postgres` home
depending on Linux distributive).

    LD_PRELOAD='/usr/local/lib/hugetlb.so'
    export LD_PRELOAD

On modern systems you can setup `libhugetlbfs0` package for this
purpose. Install it instead of building `hugetlb` and add
`libhugetlbfs0.so` to the environment instead of `hugetlb.so` along
with setting huge pages to be used with shared memory.

    HUGETLB_SHM=yes
    LD_PRELOAD='/usr/lib/libhugetlbfs.so'
    export HUGETLB_SHM
    export LD_PRELOAD

You also need to remember about setting enough memory locking
limits. It must not be less than shared memory amount plus required
memory for connections. Let us set it to 64GB in
`/etc/security/limits.conf`.

    postgres        soft    memlock          68719476736
    postgres        hard    memlock          68719476736

To check if it is used by postgres execute the following command.

    pmap -x PID | grep hugetlb.so

Where `PID` is a process ID of any running postgres process.

And this one to check if it used at all.

    cat /proc/meminfo | grep -i huge

On FreeBSD you will also need to update `/boot/loader.conf` with
`SEMMNS` and `SEMMNI` settings, see PostgreSQL documentation for more
information about them.

    kern.ipc.semmns=32000
    kern.ipc.semmni=128

It requires you to reboot.

Transparent huge pages defragmentation could lead to unpredictable
database stalls on some Linux kernels. The recommended settings for
this are below. Add them to `/etc/rc.local`.

    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    echo madvise > /sys/kernel/mm/transparent_hugepage/defrag

For NUMA hardware users on Linux turn off the NUMA local pages reclaim
as it leads to wrong caching strategy for databases.

    vm.zone_reclaim_mode = 0

Again on NUMA systems it is recommended to set memory interleaving
mode for better performance. The following should show the only node
if this mode is on.

    numactl --hardware

Usually it can be set in BIOS however if it is not set this way you
can start the database manually with this option.

    numactl --interleave=all /etc/init.d/postgresql start

Now adjust your `/etc/fstab`. 

Set `noatime,nobarrier` to gain better performance for data
partitions. Due to the known XFS allocation issue in some recent Linux
kernels that leads to significant database bloats it is recommended to
set `allocsize=1m` if you use XFS of course.

    /data xfs noatime,nobarrier,allocsize=1m

Remount affected mount points or reboot.

On Linux add the appropriate `blockdev` settings. Usually good
settings for modern systems looks like it is shown below. Add them to
`rc.local`.

    echo noop > /sys/block/sda/queue/scheduler
    echo 16384 > /sys/block/sda/queue/read_ahead_kb

Do not forget about open files limit. For modern servers a good value
is 65535.

    ulimit -n 65535

Install all the required locales.

Adjust `postgresql.conf`, `pg_hba.conf` and connection pooler
configuration (and probably its users configuration). Restart
PostgreSQL and the connection pooler.

[1]: http://oss.linbit.com/hugetlb/
