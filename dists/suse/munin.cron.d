#
# cron-jobs for munin
#

MAILTO=root

*/5 * * * *     munin test -x /usr/bin/munin-cron && /usr/bin/munin-cron
