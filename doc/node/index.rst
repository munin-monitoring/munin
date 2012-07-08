.. _node-index:

================
 The Munin node
================

Role
====

The munin node is installed on all monitored servers. It accepts
connections from the munin master, and runs plugins on demand.

By default, it is started at boot time, listens on port 4949/TCP,
accepts connections from the :ref:`munin master <master-index>`, and
runs :ref:`munin plugins <plugin-index>` on demand.

Configuration
=============

The configuration file is :ref:`munin-node.conf`.

Other documentation
===================

.. toctree::
   :maxdepth: 2

   async.rst
