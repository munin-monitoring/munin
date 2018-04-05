.. _reference-directories:

=============
 Directories
=============

.. _dbdir:

dbdir
=====

This directory (usually ``/var/lib/munin``) is used to store the Munin master database.

It contains subdirectories for the RRD files per group of hosts as well as files to store variable states that the munin master will need.

The RRD files are named in the following way: ``<dbdir>/<group>/<nodename>-<servicename>-<fieldname>-[acdg].rrd``

Example:

::

  /var/lib/munin/SomeGroup/foo.example.com-cpu-irq-d.rrd
                 --------- --------------- --- --- -
                     |            |         |   |  `-- Data type (a = absolute, c = counter, d = derive, g = gauge)
                     |            |         |   `----- Field name / data source: 'irq'
                     |            |         `--------- Plugin name: 'cpu'
                     |            `------------------- Node name: 'foo.example.com'
                     `-------------------------------- Group name: 'SomeGroup'


.. _plugindir:

plugindir
=========

This directory (usually ``/usr/share/munin/plugins``) contains all the plugins **available** to run on the node.

.. _servicedir:

servicedir
==========

This directory (usually ``/etc/munin/plugins``) contains symlinks to all the plugins that **are selected** to run on the node.
These will be shown when we are connected to :ref:`munin node <munin-node>` and say ``list``.

.. _pluginconfdir:

pluginconfdir
=============

This directory (usually ``/etc/munin/plugin-conf.d``) contains plugin configuration.

.. _rundir:

rundir
======

This directory (usually ``/var/run/munin``) contains files needed to track the munin run state. PID
files, lock files, and possibly sockets.

.. _logdir:

logdir
======

**Attention!** On a host where Munin master resides there may be two of them! One (usually ``/var/log/munin``) contains the log files for Munin master related applications and another (usually ``/var/log/munin-node``) contains the logfiles of :ref:`munin node <munin-node>`.
