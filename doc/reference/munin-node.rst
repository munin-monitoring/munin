.. _munin-node:

.. program:: munin-node

============
 munin-node
============

DESCRIPTION
===========

munin-node is a daemon for reporting statistics on system performance.

By default, it is started at boot time, listens on port 4949/TCP,
accepts connections from the :ref:`munin master <master-index>`, and
runs :ref:`munin plugins <plugin-index>` on demand.

OPTIONS
=======

.. option:: --config <configfile>

   Use <file> as configuration file. [/etc/munin/munin-node.conf]

.. option:: --paranoia

   Only run plugins owned by root. Check permissions as well. Can be
   negated with --noparanoia [--noparanoia]

.. option:: --help

   View this help message.

.. option:: --debug

   View debug messages.

   .. note::

      This can be very verbose.

.. option:: --pidebug

   Plugin debug. Sets the environment variable :envvar:`MUNIN_DEBUG`
   to 1 so that plugins may enable debugging.

CONFIGURATION
=============

The configuration file is :ref:`munin-node.conf`.

.. index::
   pair: example; munin-node.conf

FILES
=====

:ref:`/etc/munin/munin-node.conf <munin-node.conf>`

:ref:`/etc/munin/plugins/* <servicedir>`

:ref:`/etc/munin/plugin-conf.d/* <pluginconfdir>`

:ref:`/var/run/munin/munin-node.pid <rundir>`

:ref:`/var/log/munin/munin-node.log <logdir>`

SEE ALSO
========

:ref:`munin-node.conf`

Example configuration
=====================

::

  # /etc/munin/munin-node.conf - config-file for munin-node
  #

  host_name random.example.org
  log_level 4
  log_file /var/log/munin/munin-node.log
  pid_file /var/run/munin/munin-node.pid
  background 1
  setsid 1

  # Which port to bind to;

  host [::]
  port 4949
  user root
  group root

  # Regexps for files to ignore

  ignore_file ~$
  ignore_file \.bak$
  ignore_file %$
  ignore_file \.dpkg-(tmp|new|old|dist)$
  ignore_file \.rpm(save|new)$
  ignore_file \.puppet-bak$

  # Hosts to allow

  cidr_allow 127.0.0.0/8
  cidr_allow 192.0.2.129/32

SEE ALSO
========

See :ref:`munin` for an overview over munin.
