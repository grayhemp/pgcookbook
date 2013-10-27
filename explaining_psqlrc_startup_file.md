# PgCookbook - a PostgreSQL documentation project

## Explaining .psqlrc Startup File

This description is not a general explanation of the functionality. It
is just a configuration that seems me to be useful. It is subjective.

The size of the `psql` history is 500 entries by default. It is too
small when experimenting with query plans or building test cases. So
it worth to increase it, for example to 5000.

    \set HISTSIZE 5000

Just not to waste resources and prevent users from occasional missing
`LIMIT` fetch count is set to 1000.

    \set FETCH_COUNT 1000

Get rid of duplicate sequences in the history.

    \set HISTCONTROL ignoredups

Display prompt as `host:post user@database=#`. The `=` is changing to
different symbols depending on context, if you are writing a comment
it is `*`, inside of a string it is `'` or `"`, in a single line mode
it is `^`, etc. `#` is displayed with superusers, `>` with common
user.

    \set PROMPT1 '%M:%> %n@%/%R%# '
    \set PROMPT2 :PROMPT1
    \set PROMPT3 '>> '

Default pagers are often spoil expected output so it is turned off.

    \pset pager off

To know the execution time of such directives like `ALTER` or `CREATE
TRIGGER` is very useful. However by default it is does not shown. So
turn it on.

    \timing

This [.psqlrc][] file can be found in the repository.
