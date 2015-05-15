zgrep -E 'ERROR|FATAL|WARNING|PANIC' /var/log/postgresql/postgresql.log \
    | sed -r 's/^.*(ERROR|FATAL|WARNING|PANIC):  /\1 /' \
    | sort | uniq -c | sort -n
