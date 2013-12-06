# PgCookbook - a PostgreSQL documentation project

## SSH without Password Setup

Often, when dealing with more than one database server, you need to
have an easy file system level access configured between them. For
example to exchange configuration files, make base backups, copy some
maintenance scripts, etc. SSH configured without password will save
you a lot of time here.

Let us see how to set it up. 

Suppose you need to get rid of entering password when logging in via
SSH from `user1@host1` to `user2@host2`.

First, create an `.ssh' directory and generate a public key on `host1`
with `user1`.

    mkdir ~/.ssh/
    chmod 700 ~/.ssh/
    ssh-keygen -t rsa
    cat ~/.ssh/id_rsa.pub 
    ssh-rsa AAA...
    ...qCXpQ== user1@host1

Append the key to the end of `~/.ssh/authorized_keys` (or
`~/.ssh/authorized_keys2` if SSH2 is used).

    cat <<EOF >> ~/.ssh/authorized_keys 
    > ssh-rsa AAA...
    ...qCXpQ== user1@host1

Enjoy.

    scp ~/some/file user2@host2:~/
    ssh user2@host2
