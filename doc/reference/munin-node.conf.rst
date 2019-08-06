.. _munin-node.conf:

===============
munin-node.conf
===============

DESCRIPTION
===========

This is the configuration file for :ref:`munin-node` and :ref:`munin-run`.

The directives "host_name", "paranoia" and "ignore_file" are munin
node specific.

All other directives in munin-node.conf are passed through to the Perl
module Net::Server. Depending on the version installed, you may have
different settings available.

DIRECTIVES
==========

Native
------

.. option:: host_name

   The hostname used by munin-node to present itself to the munin
   master. Use this if the local node name differs from the name
   configured in the munin master.

.. option:: ignore_file

   Files to ignore when locating installed plugins. May be repeated.

.. option:: paranoia

   If set to a true value, :ref:`munin-node` will only run plugins
   owned by root.

Inherited
---------

These are the most common Net::Server options used in
:ref:`munin-node`.

.. option:: log_level

   Ranges from 0-4. Specifies what level of error will be logged. "0"
   means no logigng, while "4" means very verbose. These levels
   correlate to syslog levels as defined by the following key/value
   pairs. 0=err, 1=warning, 2=notice, 3=info, 4=debug.

   Default: 2

.. option:: log_file

   Where the munin node logs its activity. If the value is
   Sys::Syslog, logging is sent to syslog

   Default: undef (STDERR)

.. option:: port

   The TCP port the munin node listens on

   Default: 4949

.. option:: pid_file

   The pid file of the process

   Default: undef (none)

.. option:: background

   To run munin node in background set this to "1". If you want
   munin-node to run as a foreground process, comment this line out
   and set "setsid" to "0".

.. option:: host

   The IP address the munin node process listens on

   Default: * (All interfaces)

.. option:: user

   The user munin-node runs as

   Default: root

.. option:: group

   The group munin-node runs as

   Default: root

.. option:: setsid

   If set to "1", the server forks after binding to release itself
   from the command line, and runs the POSIX::setsid() command to
   daemonize.

   Default: undef

.. option:: ignore_file

   Files to ignore when locating installed plugins. May be repeated.

.. option:: host_name

   The hostname used by munin-node to present itself to the munin
   master. Use this if the local node name differs from the name
   configured in the munin master.

.. option:: allow

   A regular expression defining which hosts may connect to the munin
   node.

   .. note:: Use cidr_allow if available.

.. option:: cidr_allow

   Allowed hosts given in CIDR notation (192.0.2.1/32). Replaces or
   complements “allow”. Requires the presence of Net::Server, but is
   not supported by old versions of this module.

.. option:: cidr_deny

   Like cidr_allow, but used for denying host access

.. option:: timeout

   Number of seconds after the last activity by the master until the
   node will close the connection.

   If plugins take longer to run, this may disconnect the master.

   Default: 20 seconds

EXAMPLE
=======

.. index::
   tuple: munin-node.conf; example

A pretty normal configuration file:

::

  host *
  port 4949

  cidr_allow 127.0.0.0/8
  cidr_allow 192.0.2.0/24

  user       root
  group      root
  background 1
  setsid     1

  log_level 4
  log_file  /var/log/munin/munin-node.log
  pid_file  /var/run/munin-node.pid

  ignore_file \.bak$
  ignore_file ^README$
  ignore_file \.dpkg-(old|new)$
  ignore_file \.rpm(save|new)$
  ignore_file \.puppet-new$

SEE ALSO
========

:ref:`munin-node`, :ref:`munin-run`
