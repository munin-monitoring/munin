.. _plugin-index:

==================
 The Munin plugin
==================

Role
====

The munin plugin is a simple executable, which role is to gather one
set of facts about the local server (or fetching data from a remote machine via SNMP)

The plugin is called with the argument "config" to get metadata, and
with no arguments to get the values. These are mandatory arguments for each plugin.
We have some more standard arguments, which play a role in the process of automatic configuration. 
Read more in the docs listed below.

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
