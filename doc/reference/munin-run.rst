.. _munin-run:

.. program:: munin-run

===========
 munin-run
===========

DESCRIPTION
===========

munin-run is a script to run Munin plugins from the command-line.

It is primarily used to debug plugins; munin-run runs these plugins in
the same conditions as they are under :ref:`munin-node`.

OPTIONS
=======

.. option:: --config <configfile>

   Use <file> as configuration file. [/etc/munin/munin-node.conf]

.. option:: --servicedir <dir>

   Use <dir> as plugin dir. [/etc/munin/plugins/]

.. option:: --sconfdir <dir>

   Use <dir> as plugin configuration dir. [/etc/munin/plugin-conf.d/]

.. option:: --sconffile <file>

   Use <file> as plugin configuration. Overrides sconfdir. [undefined]

.. option:: --paranoia

   Only run plugins owned by root and check permissions. [disabled]

.. option:: --help

   View this help message.

.. option:: --debug

   Print debug messages.

   Debug messages are sent to STDOUT and are prefixed with "#" (this
   makes it easier for other parts of munin to use munin-run and still
   have --debug on). Only errors go to STDERR.

.. option:: --pidebug

   Enable debug output from plugins. Sets the environment variable
   :envvar:`MUNIN_DEBUG` to 1 so that plugins may enable debugging.
   [disabled]

.. option:: --version

   Show version information.

FILES
=====

:ref:`/etc/munin/munin-node.conf <munin-node.conf>`

:ref:`/etc/munin/plugins/* <servicedir>`

:ref:`/etc/munin/plugin-conf.d/* <pluginconfdir>`

:ref:`/var/run/munin/munin-node.pid <rundir>`

:ref:`/var/log/munin/munin-node.log <logdir>`

SEE ALSO
========

See :ref:`munin` for an overview over munin.
