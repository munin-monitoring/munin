.. _plugin-index:

==================
 The Munin plugin
==================

Role
====

A Munin plugin is a simple executable, whose role is to gather one
set of facts on a host and present them in a format Munin can use to analyze. 

A plugin is usually called without any arguments.  When this happens, it returns 
the data it is configured to gather, in a 'key value' format.  For 
example, the 'load' plugin, which comes standard with Munin, will output the current
system load::

 # munin-run load
 load.value 0.03

All plugins must also support the argument 'config' to get metadata on the plugin::
 # munin-run load config
 graph_title Load average
 graph_args --base 1000 -l 0
 graph_vlabel load
 graph_scale no
 graph_category system
 load.label load
 graph_info The load average of the machine describes how many processes are in the run-queue (scheduled to run "immediately").
 load.info 5 minute load average
 
Plugins may support other arguments, but the two cases described above will work for any plugin.

How to use
==========

Learn it here :ref:`How to use Munin plugins <plugin-use>`.

.. toctree::
   :maxdepth: 2

   use.rst

How to write
============

Learn it here :ref:`How to write Munin plugins <plugin-writing>`.

.. toctree::
   :maxdepth: 2

   writing.rst
   writing-tips.rst

Other documentation
===================

.. toctree::
   :maxdepth: 2

   env.rst
   multigraphing.rst
   supersampling.rst
   snmp.rst
