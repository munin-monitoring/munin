.. _munin-asyncd:

.. program:: munin-asyncd

==============
 munin-asyncd
==============

DESCRIPTION
===========

The munin async daemon connects to a :ref:`munin node <munin-node>`
periodically, and requests plugin configuration and data.

This is stored in a spool directory, which is read by
:ref:`munin-async`.

OPTIONS
=======

.. option:: --spool | -s <spooldir>

   Directory for spooled data [/var/lib/munin/spool]

.. option:: --host <hostname:port>

   Connect a munin node running on this host name and port
   [localhost:4949]

.. option:: --interval <seconds>

   Set default interval size [86400 (one day)]

.. option:: --retain <count>

   Number of interval files to retai [7]

.. option:: --nocleanup

   Disable automated spool dir cleanup

.. option:: --fork

   Fork one thread per plugin available on the node. [no forking]

.. option:: --verbose | -v

   Be verbose

.. option:: --help | -h

   View this message

SEE ALSO
========

See also :ref:`node-async` for more information and examples of how to
configure munin-asyncd.
