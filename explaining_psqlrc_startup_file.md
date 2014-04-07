# PgCookbook - a PostgreSQL documentation project

## Explaining .psqlrc Startup File

The file `.psqlrc` serves as a user's start-up file for the `psql`
interactive terminal. There also is a system-wide `psqlrc` file. This
description is neither a general explanation of its functionality nor
a set of rules. It is just one of the configuration examples, supplied
with notes, that seems to be useful and might serve as a starting
point.

The size of the `psql` history is 500 entries by default. Often it is
too few, mostly if one is actively working with query plans, building
test cases, etc. It worth to increase it, eg. to 5000.

    \set HISTSIZE 5000

To prevent users from accidentally missing `LIMIT` when querying a
huge data set the fetch count to 1000.

    \set FETCH_COUNT 1000

Avoid duplication in the history.

    \set HISTCONTROL ignoredups

Display prompt as `host:post user@database=# `. The `=` symbol changes
to other symbols depending on a context. If you are writing a comment
it is `*`, inside of a string `'` or `"`, in a single line mode `^`,
etc. The `#` symbol is displayed for superusers, `>` for common users.

    \set PROMPT1 '%M:%> %n@%/%R%# '
    \set PROMPT2 :PROMPT1
    \set PROMPT3 '>> '

Pagers often spoil output so it is probably worth to turn the
following off. Surely it depends on everyone's preferences.

    \pset pager off

Often it is useful to know execution time of such commands like
`ALTER` or `CREATE INDEX`, but it is not shown by default. So turn it
on like this.

    \timing

You can find the [.psqlrc](.psqlrc) file containing all the described
above itself in [PgCookbook](README.md).
