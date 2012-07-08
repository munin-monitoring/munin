.. _munin-update:

.. program:: munin-update

==============
 munin-update
==============

DESCRIPTION
===========

munin-update is the primary Munin component. It is run from the
:ref:`munin-cron` script.

This script is responsible for contacting all the agents
(munin-nodes) and collecting their data. Upon fetching the data,
munin-update stores everything in RRD files - one RRD files for
each field in each plugin.

Running munin-update with the --debug flag will often give plenty
of hints on what might be wrong.

munin-update is a component in the Munin server.

OPTIONS
=======

.. option:: --config_file <file>

   Use <file> as the configuration file. [/etc/munin/munin.conf]

.. option:: --debug

   If set, log debug messages. Can be negated with --nodebug
   [--nodebug]

.. option:: --fork

   If set, will fork off one process for each host. Can be negated
   with --nofork [--fork]

.. option:: --host <host>

   Limit fetched data to those from <host<gt>. Multiple --host options
   may be supplied. [unset]

.. option:: --service <service>

   Limit fetched data to those of <service>. Multiple --service
   options may be supplied. [unset]

.. option:: --timeout <seconds>

   Set the network timeout to <seconds>. [180]

.. option:: --help

   Print the help message then exit.

.. option:: --version

   Print version information then exit.


SEE ALSO
========

:ref:`munin-cron`
