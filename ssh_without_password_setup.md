# PgCookbook - a PostgreSQL documentation project

## SSH without Password Setup

Often, when dealing with more than one database server, one needs to
have an easy shell level access configured between them. For example
to exchange with configuration files, make base backups, copy some
maintenance scripts, etc. SSH configured with key based authorization
(without password) will save a lot of time and efforts here.

Now, let us see how to set it up from `user1@host1` to `user2@host2`.

First, generate a public key on `host1` when logged in with
`user1`. Do not enter any passphrase.

    ssh-keygen -t rsa

Then, using `ssh` with `user2@host2`, create an `.ssh` directory,
change an access mode to 700 on it, and append the generated key to
the end of `~/.ssh/authorized_keys` (or `~/.ssh/authorized_keys2` if
SSH2 is used) there. You will need to enter `user2`s password two
times here.

    ssh user2@host2 'mkdir ~/.ssh/ && chmod 700 ~/.ssh/'
    cat ~/.ssh/id_rsa.pub | ssh user2@host2 'cat >> ~/.ssh/authorized_keys'

And finally you can enjoy it without password.

    ssh user2@host2
    scp ~/some/file user2@host2:~/ 
