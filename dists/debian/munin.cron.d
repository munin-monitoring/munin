#
# cron-jobs for lrrd-server
#

MAILTO=root

*/5 * * * *     lrrd if [ -x /usr/bin/lrrd-cron ]; then /usr/bin/lrrd-cron; fi
10 10 * * *     lrrd if [ -x /usr/share/lrrd/lrrd-nagios ]; then /usr/share/lrrd/lrrd-nagios --removeok; fi
