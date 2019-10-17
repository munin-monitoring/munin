.. _reference-directories:

=============
 Directories
=============

.. _dbdir:

dbdir
=====

This directory is used to store the munin master database.

It contains one subdirectory with RRD files per group of hosts, as
well as other variable state the munin master would need.

.. _plugindir:

plugindir
=========

This directory contains all the plugins the :ref:`munin node
<munin-node>` should run.

.. _pluginconfdir:

pluginconfdir
=============

This directory contains plugin configuration.

.. _rundir:

rundir
======

This directory contains files needed to track the munin run state. PID
files, lock files, and possibly sockets.

.. _logdir:

logdir
======

Contains the log files for each munin program.
