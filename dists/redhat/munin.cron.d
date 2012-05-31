#
# cron-jobs for munin
#

MAILTO=root

*/5 * * * *     munin test -x /usr/bin/munin-cron && /usr/bin/munin-cron
14 10 * * *     munin test -x /usr/share/munin/munin-limits && /usr/share/munin/munin-limits --force --contact nagios --contact old-nagios
