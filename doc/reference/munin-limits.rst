.. _munin-limits:

.. program:: munin-limits

==============
 munin-limits
==============

DESCRIPTION
===========

:ref:`munin-limits` is one of the processes regularly run from the
:ref:`munin-cron` script.

It reads the current and the previous collected values for each
plugin, and compares them to the plugin's warning and critical values,
if it has any.

If the limits are breached, for instance, if a value moves from "ok"
to "warning", or from "critical" to "ok", it sends an event to any
configured contacts.

A common configured contact is "nagios", which can use events from
munin-limits as a source of passive service check results.

OPTIONS
=======

.. option:: --config <file>

   Use <file> as configuration file. [/etc/munin/munin.conf]

.. option:: --contact <contact>

   Limit contacts to those of <contact<gt>. Multiple --contact options
   may be supplied. [unset]

.. option:: --host <host>

   Limit hosts to those of <host<gt>. Multiple --host options may be
   supplied. [unset]

.. option:: --service <service>

   Limit services to those of <service>. Multiple --service options
   may be supplied. [unset]

.. option:: --always-send <severity list>

   Force sending of messages even if you normally wouldn't.

   The <severity list> can be a whitespace or comma separated list of
   the values "ok", "warning", "critical" or "unknown".

   This option may be specified several times, to add more values.

   Use of "--always-send" overrides the "always_send" value in
   munin.conf for configured contacts.  See also --force.

.. option:: --force

   Alias for "--always-send ok,warning,critical,unknown"

.. option:: --force-run-as-root

   munin-limits will normally prevent you from running as root. Use
   this option to override this.

   The use of this option is not recommended. You may have to clean up
   file permissions in order for munin to run normally afterwards.

.. option:: --help

   View help message.

.. option:: --debug

   If set, view debug messages. Can be negated with --nodebug.
   [--nodebug]

FILES
=====

:ref:`/etc/munin/munin.conf <munin.conf>`

:ref:`/var/lib/munin/* <dbdir>`

:ref:`/var/run/munin/* <rundir>`

SEE ALSO
========

:ref:`munin.conf`
