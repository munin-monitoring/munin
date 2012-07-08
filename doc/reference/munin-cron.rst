.. _munin-cron:

.. program:: munin-cron

============
 munin-cron
============


.. object:: NAME

   munin-cron - Cron script for the munin master

.. object:: DESCRIPTION

   Munin-cron is a part of the package Munin, which is used in
   combination with :ref:`munin-node`.

   Munin is a group of programs to gather data from Munin's nodes,
   graph them, create html-pages, and optionally warn Nagios about any
   off-limit values.

   "munin-cron" runs the following programs, in the given order:

   #. :ref:`munin-update`
   #. :ref:`munin-limits`
   #. :ref:`munin-graph`
      (unless configured to run from CGI)
   #. :ref:`munin-html`
      (unless configured to run from CGI)

   Unless the munin master is configured otherwise, "munin-cron"
   should run every 5 minutes.

.. object:: OPTIONS

   .. option:: --service <service>

      Limit services to <service>. Multiple --service options may be
      supplied. [unset]

   .. option:: --host <host>

      Limit hosts to <host>. Multiple --host options may be supplied.
      [unset]

   .. option:: --config <file>

      Use <file> as configuration file. [/etc/munin/munin.conf]

.. object:: AUTHORS

   Audun Ytterdal and Jimmy Olsen.

.. object:: COPYRIGHT

   2002-2008 Audun Ytterdal and Jimmy Olsen / Linpro AS.
