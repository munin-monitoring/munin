#
# cron-jobs for munin
#

MAILTO=root

*/5 * * * *     munin if [ -x /usr/bin/munin-cron ]; then /usr/bin/munin-cron; fi
14 10 * * *     munin if [ -x /usr/share/munin/munin-limits ]; then /usr/share/munin/munin-limits --force --contact nagios --contact old-nagios; fi

# remove stale generated html and graph files (e.g. disabled plugins or fields with volatile names)
27 03 * * *     munin htmldir=$({ cat /etc/munin/munin.conf /etc/munin/munin-conf.d/* 2>/dev/null || true; } | sed -nE 's/^\s*htmldir\s+(\S.*)$/\1/p' | tail -1); htmldir=${htmldir:-/var/cache/munin/www}; if [ -d "$htmldir" ]; then find "$htmldir/" -type f -name "*.html" -mtime +30 -delete; find "$htmldir/" -mindepth 1 -type d -empty -delete; fi
32 03 * * *     www-data cgitmpdir=$({ cat /etc/munin/munin.conf /etc/munin/munin-conf.d/* 2>/dev/null || true; } | sed -nE 's/^\s*cgitmpdir\s+(\S.*)$/\1/p' | tail -1); cgitmpdir=${cgitmpdir:-/var/lib/munin/cgi-tmp}; if [ -d "$cgitmpdir" ]; then find "$cgitmpdir/" -type f -mtime +1 -delete; find "$cgitmpdir/" -mindepth 1 -type d -empty -delete; fi
