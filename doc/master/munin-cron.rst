.. _munin-cron:

============
 munin-cron
============

"munin-cron" runs the following programs, in the given order:

1. :ref:`munin-update`
2. :ref:`munin-limits`
3. :ref:`munin-html` (unless configured to run from CGI)

Unless the munin master is configured otherwise, "munin-cron" should
run every 5 minutes.
