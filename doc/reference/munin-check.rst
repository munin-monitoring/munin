.. _munin-check:

.. program:: munin-check

=============
 munin-check
=============

DESCRIPTION
===========

munin-check is a utility that fixes the permissions of the munin
directories and files.

.. note:: munin-check needs superuser rights.

.. note::

   Please don't use this script if you are using 'graph_strategy cgi'.
   It doesn't care about the right permissions for www-data yet.


OPTIONS
=======

.. option:: --fix-permissions | -f

   Fix the permissions of the munin files and directories.

.. option:: --help | -h

   Display usage information
