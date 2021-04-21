.. _plugin-index:

==================
 The Munin plugin
==================

Introduction
============

A Munin plugin is a simple executable invoked in a command line environment whose role is to gather a
set of facts on a host and present them in a format Munin can use.

A plugin is usually called without any arguments.  In this circumstance, the plugin returns
the data in a 'key value' format.  For
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

See Also
========

* :ref:`How to use Munin plugins <plugin-use>`.
* :ref:`How to write your own Munin plugins <plugin-writing>`.
