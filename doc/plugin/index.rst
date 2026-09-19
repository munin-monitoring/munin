.. _plugin-index:

=========================
 The Munin Plugin System
=========================

A Munin plugin is a small executable that gathers one type of data about
a host and presents it in a format Munin can graph. Plugins are the
building blocks of Munin — they make it possible to monitor anything
that can be expressed as a number.

Quick Example
=============

When called without arguments, a plugin outputs its current values:

.. code-block:: bash

   $ munin-run load
   load.value 0.03

When called with ``config``, it outputs metadata (graph title, labels,
thresholds):

.. code-block:: bash

   $ munin-run load config
   graph_title Load average
   graph_args --base 1000 -l 0
   graph_vlabel load
   graph_scale no
   graph_category system
   load.label load
   graph_info The load average of the machine describes how many processes
              are in the run-queue (scheduled to run "immediately").
   load.info 5 minute load average

For users
=========

- :ref:`How to install and configure plugins <plugin-use>`
- :ref:`Using wildcard plugins <tutorial-plugins-wildcard>`
- :ref:`Configuring plugin environment <plugin-conf.d>`
- :ref:`Downloading plugins with munin-get <munin-get>`

For plugin authors
==================

- :ref:`Writing a plugin <plugin-writing>` — minimal example and core concepts
- :ref:`Plugin protocol reference <plugin-reference>` — all config and data attributes
- :ref:`Multigraph plugins <plugin-multigraphing>` — multiple graphs from one plugin
- :ref:`SNMP plugins <plugin-snmp>` — monitoring via SNMP
- :ref:`Dirty config protocol <plugin-protocol-dirtyconfig>` — performance optimization
- :ref:`Plugin magic markers <magic-markers>` — autoconf, family, capabilities

Plugin Helper Modules
=====================

Munin provides Perl modules to simplify plugin development:

- ``Munin::Plugin`` — state file management, threshold handling, utilities
- ``Munin::Plugin::SNMP`` — SNMP plugin framework
- ``Munin::Plugin::HTTP`` — HTTP plugin framework
- ``Munin::Plugin::Pgsql`` — PostgreSQL plugin framework

Use them with:

.. code-block:: perl

   use lib $ENV{'MUNIN_LIBDIR'};
   use Munin::Plugin;

Plugin Languages
================

Plugins can be written in any language that can print key-value pairs to
stdout. Common choices:

- **Shell** — simplest, no dependencies
- **Perl** — most helper modules available
- **Python** — good for complex data collection
- **Ruby**, **PHP**, **Java** — all work

The only requirement is that the script is executable and outputs lines
in the format ``key.value number`` for data and ``key value`` for config.

Debugging Plugins
=================

Test a plugin from the command line:

.. code-block:: bash

   # Run with config
   sudo munin-run myplugin config

   # Run and fetch values
   sudo munin-run myplugin

   # Run with debug output
   sudo munin-run --pidebug myplugin

   # Run via the network protocol
   nc localhost 4949
   fetch myplugin
   config myplugin

Check ``/var/log/munin/munin-node.log`` for errors from plugins run
via ``munin-node``.

Finding Plugins
===============

- **Built-in**: ``/usr/share/munin/plugins/`` — installed with munin-node
- **Contrib**: `github.com/munin-monitoring/contrib <https://github.com/munin-monitoring/contrib>`_
- **Gallery**: `gallery.munin-monitoring.org <https://gallery.munin-monitoring.org/>`_

Use ``munin-get`` to install plugins from the contrib repository:

.. code-block:: bash

   munin-get install <plugin-name>
