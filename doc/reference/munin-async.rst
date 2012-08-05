.. _munin-async:

.. program:: munin-async

=============
 munin-async
=============

DESCRIPTION
===========

The munin async clients reads from a spool directory written by
:ref:`munin-asyncd`.

It can optionally request a cleanup of this directory.

OPTIONS
=======

.. option:: --spooldir | -s <spooldir>

   Directory for spooled data [/var/lib/munin/spool]

.. option:: --hostname <hostname>

   Overrides the hostname [The local hostname]

   This is used to override the hostname used in the greeting
   banner. This is used when using munin-async from the munin
   master, and the data fetched is from another node.

.. option:: --cleanup

   Clean up the spooldir after interactive session completes

.. option:: --cleanupandexit

   Clean up the spooldir and exit (non-interactive)

.. option:: --spoolfetch

   Enables the "spool" capability [no]

.. option:: --vectorfetch

   Enables the "vectorized" fetching capability [no]

   Note that without this flag, the "fetch" command is disabled.

.. option:: --verbose | -v

   Be verbose

.. option:: --help | -h

   View this message

EXAMPLES
========

.. code-block:: bash

   munin-async --spoolfetch

This starts an interactive munin node session, enabling the
"spoolfetch" command. This does not connect to the local munin node.
Everything happens within munin-async, which reads from the spool
directory instead of connecting to the node.

SEE ALSO
========

See also :ref:`node-async` for more information and examples of how to
configure munin-async.
