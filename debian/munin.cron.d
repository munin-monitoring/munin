#
# cron-jobs for munin
#

MAILTO=root

*/5 * * * *     munin if [ -x /usr/bin/munin-cron ]; then /usr/bin/munin-cron; fi
14 10 * * *     munin if [ -x /usr/share/munin/munin-limits ]; then /usr/share/munin/munin-limits --force --contact nagios --contact old-nagios; fi

# remove stale generated html and graph files (e.g. disabled plugins or fields with volatile names)
27 03 * * *     munin if [ -d /var/cache/munin/www ]; then find /var/cache/munin/www/ -type f -name "*.html" -mtime +30 -delete; find /var/cache/munin/www/ -mindepth 1 -type d -empty -delete; fi
32 03 * * *     www-data if [ -d /var/lib/munin/cgi-tmp ]; then find /var/lib/munin/cgi-tmp/ -type f -mtime +1 -delete; find /var/lib/munin/cgi-tmp/ -mindepth 1 -type d -empty -delete; fi
