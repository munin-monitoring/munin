#
# cron-jobs for munin
#

MAILTO=root

*/5 * * * *     munin test -x /usr/bin/munin-cron && /usr/bin/munin-cron
10 10 * * *     munin test -x /usr/share/munin/munin-nagios && /usr/share/munin/munin-nagios --removeok
