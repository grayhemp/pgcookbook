# PgCookbook - a PostgreSQL documentation project

## Database Server Configuration

This text describes a check list you need to follow when configuring a
new database server.

Check if the server is available by SSH and that necessary permissions
are granted. Depending on the situation you might need to `sudo` as
`postgres` or `root` user to control PostgreSQL and assisting
software, like replication tools, connection poolers, system utilities
and to manage configuration.

    sudo -l

If you are migrating a database to the server or setting up a hot
standby ensure that all the required mount points for tablespaces are
created. Use `\db+` in psql to check tablespaces and their
locations.

Ensure that the required version of PotsgreSQL is installed. If it is
not, then install the packages and initialize a cluster. Also check
and install all the needed satellite software, like replication
systems and connection poolers.

Linux kernel version notes:

- if you are on the kernel 3.2, than it is worth to upgrade it due to
  a significant read performance downgrade;
- you should upgrade to 3.13 or a later version due to the IO issues
  fixes dramatically improving IO consumption for reads.

A lot of configuration parameters we are going set do will be in
`sysctl.conf`. To not reboot the server, these settings can be set
like it is shown below. You'll need `sudo` to do this.

    sysctl -w some.parameter=some_value

Or just like this, after `sysctl.conf` will be completed, to not do it
one by one.

    sysctl -p /etc/sysctl.conf

If you are on `>=9.3` you not longer need this step, otherwise set the
`SHMMAX` and `SHMALL` kernel settings accordingly to the shared
buffers amount assumed to be used.

Several notes on shared buffers. Shared buffers must (currently)
compete with OS inode caches. If shared buffers are too high, much of
the cached data is already cached by the operating system, and you end
up with wasted RAM. However in some cases larger shared buffers might
be preferable to OS cache, mostly if you have a huge amount of active
data, because PostgreSQL often works with memory a more effective
way. Checkpoints must commit dirty shared buffers to disk. The larger
it is, the more slowdown risk you have when checkpoints come. Since
shared_buffers is the amount of memory that could potentially remain
uncommitted to data files, the larger this is, the longer crash
recovery can take. The checkpoints and bgwriter settings control how
this is distributed and maintained, so, it is often worth configuring
them more aggressively if you set a large shared buffers.

Now, let us assume that we want to set PostgreSQL shared buffers to
25% of RAM. Note that `SHMMAX/SHMALL` should be slightly larger then
shared buffers. So let us set `SHMMAX/SHMALL` to 30% of RAM.

Calculate them like this. If you use FreeBSD use `sysctl -n
hw.availpages` instead of `getconf _PHYS_PAGES`.

    _SHMALL=$(expr $(getconf _PHYS_PAGES) \* 30 / 100)
    _SHMMAX=$(expr $(getconf PAGE_SIZE) \* $_SHMALL)

If you have a dedicated PostgreSQL server or no software needs
`SHMMAX/SHMALL` to be shorten, it is safe to just set it to 100% of
RAM.

For FreeBSD use `kern.ipc.*` instead of `kernel.*`.

    kernel.shmall = 179085
    kernel.shmmax = 733532160

Note, that if you 

On FreeBSD add `kern.ipc.semmap` to these settings too.

    kern.ipc.semmap=256

On FreeBSD you will also need to update `/boot/loader.conf` with
`SEMMNS` and `SEMMNI` settings, see PostgreSQL documentation for more
information about them. It requires reboot to be applied.

    kern.ipc.semmns=32000
    kern.ipc.semmni=128

Also remember about setting enough memory locking limits. It must not
be less than shared memory amount plus required memory for
connections. Let us set it to 64GB in `/etc/security/limits.conf`.

    postgres        soft    memlock          68719476736
    postgres        hard    memlock          68719476736

Turn off swapping if you need it. Note that it is not recommended to
do for low RAM servers mostly, if they are not dedicated for
PostgreSQL, because swapping might free some memory by moving some
initialization data to swap, or it might provide hints about a lack of
memory before server is out of memory.

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

And increase maximum number of open files on the system for `postgres`
in `/etc/security/limits.conf`.

    postgres        soft    nofile           65535
    postgres        hard    nofile           65535

`pdflush` tuning to prevent lag spikes for old Linux kernels (consult
with your kernel docs).

    vm.dirty_ratio = 10
    vm.dirty_background_ratio = 1
    vm.dirty_expire_centisecs = 499

`pdflush` tuning to prevent lag spikes for new Linux kernels. The
recommended estimation is 64MB and 50% of the controller cache size
accordingly if the cache size is known. Otherwise 8MB and 64MB. Look
through `dmesg` for `scsi` (hardware RAID) or `md` (software RAID) to
determine what controller is installed.

    vm.dirty_background_bytes = 8388608
    vm.dirty_bytes = 67108864

On Linux with many processes (eg. client connections) increase this
setting to prevent the scheduler's breakdown.

For kernel versions `<3.11`.

    kernel.sched_migration_cost = 5000000

For `>=3.11`.

    kernel.sched_migration_cost_ns = 5000000

It must be turned off on server Linux systems to provide more CPU to
PostgreSQL.

    kernel.sched_autogroup_enabled = 0

For NUMA hardware users on Linux turn off the NUMA local pages reclaim
as it leads to wrong caching strategy for databases.

    vm.zone_reclaim_mode = 0

Again on NUMA systems it is recommended to set memory interleaving
mode for better performance. The following should show the only node
if this mode is on.

    numactl --hardware

Usually it can be set in BIOS however, if it does not work, you can
start the database manually with this mode.

    numactl --interleave=all /etc/init.d/postgresql start

To check if it works run `cat /proc/PID/numa_maps` where `PID` is a
postgres process. You should see something like `interleave:0-1` in
every line.

Setup `hugepages` to be used by PostgreSQL on Linux. On 9.3 you can
not use this feature because of a new memory management that do not
support it. However, you can use [this patch][2] to overcome this
restriction. Hope it will be included in 9.4.

Do not forget to replace `110` with your `postgres` group in
`vm.hugetlb_shm_group`.

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

On modern Linux versions you can install `libhugetlbfs` package for
this purpose. Note it might be named as `libhugetlbfs0` or a similar
way, depending on a distribution. Install it instead of building
`hugetlb` and add `libhugetlbfs.so` to the environment instead of
`hugetlb.so` along with setting huge pages to be used with shared
memory.

    HUGETLB_SHM=yes
    LD_PRELOAD='/usr/lib/libhugetlbfs.so'
    export HUGETLB_SHM
    export LD_PRELOAD

To check if it is used by postgres execute the following command.

    pmap -x PID | grep hugetlb.so

Where `PID` is a process ID of any running postgres process.

And this one is to check if it used at all.

    cat /proc/meminfo | grep -i huge

Transparent huge pages defragmentation could lead to unpredictable
database stalls on some Linux kernels. The recommended settings for
this are below. Add them to `/etc/rc.local`.

    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    echo madvise > /sys/kernel/mm/transparent_hugepage/defrag

On Linux add the appropriate `blockdev` settings for the data
partition. Usually good settings for modern systems looks like it is
shown below. Add them to `rc.local`. To find out device names use `ls
-l /dev/disk/by-*` and `ls -l /dev/mapper/`.

    echo noop > /sys/block/sdb/queue/scheduler
    echo 16384 > /sys/block/sdb/queue/read_ahead_kb

Adjust your `/etc/fstab`. Set `noatime,nobarrier` to gain better
performance for data partitions. Due to the known XFS allocation issue
in some recent Linux kernels that leads to significant database bloats
it is recommended to set `allocsize=1m` if you use XFS of course.

    /dev/sdb /data xfs defaults,noatime,nobarrier,allocsize=1m 0 2

You will need to remount affected mount points or to reboot to make it
work.

    mount -o remount /data

XFS currently is a recommended file system for PostgreSQL. To setup
your partition in XFS `umount` it if it is mounted, and make it with
mkfs.xfs from the xfsprogs package. You might probably want to adjust
some file system options on this step.

    umount /data
    mkfs.xfs /dev/sdb

Then adjust `fstab` as it is shown above, and mount the partition.

    mount /data

To check if everything is okay list the mounted partitions.

    mount -l

Do not forget to install all the required locales.

Now adjust `postgresql.conf`, `pg_hba.conf` and connection pooler
configuration (and probably its users configuration). Restart
PostgreSQL and the connection pooler.

[1]: http://oss.linbit.com/hugetlb/
[2]: http://www.postgresql.org/message-id/flat/CA+TgmoZypzzdyVj1cpPJ9O-Nh-A9_Uqdz5w4Ete_QzMEoX01-Q@mail.gmail.com
