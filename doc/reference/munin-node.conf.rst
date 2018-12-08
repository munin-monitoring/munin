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

.. option:: pid_file

   The pid file of the process

   Default: undef (none)

.. option:: background

   To run munin node in background set this to "1". If you want
   munin-node to run as a foreground process, comment this line out
   and set "setsid" to "0".

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

.. option:: global_timeout

   :ref:`munin-node` holds the connection to Munin master only a limited number of seconds to get the requested operation finished.
   If the time runs out the node will close the connection.

   Timeout for the whole transaction. Units are in sec.

   Default: 900 seconds (15 min)

.. option:: timeout

   This is the timeout for each plugin.
   If plugins take longer to run, this will disconnect the master.

   Default: 60 seconds

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

.. option:: host

   The IP address the munin node process listens on

   Default: * (All interfaces)

.. option:: port

   The TCP port the munin node listens on

   Default: 4949

.. _example-munin-node.conf:

EXAMPLE
=======

.. index::
   tuple: munin-node.conf; example

A pretty normal configuration file:

::

  #
  # Example config-file for munin-node
  #

  log_level 4
  log_file /var/log/munin-node/munin-node.log
  pid_file /var/run/munin/munin-node.pid

  background 1
  setsid 1

  user root
  group root

  # This is the timeout for the whole transaction.
  # Units are in sec. Default is 15 min
  #
  # global_timeout 900

  # This is the timeout for each plugin.
  # Units are in sec. Default is 1 min
  #
  # timeout 60

  # Regexps for files to ignore
  ignore_file [\#~]$
  ignore_file DEADJOE$
  ignore_file \.bak$
  ignore_file %$
  ignore_file \.dpkg-(tmp|new|old|dist)$
  ignore_file \.rpm(save|new)$
  ignore_file \.pod$

  # Set this if the client doesn't report the correct hostname when
  # telnetting to localhost, port 4949
  #
  host_name localhost.localdomain

  # A list of addresses that are allowed to connect.  This must be a
  # regular expression, since Net::Server does not understand CIDR-style
  # network notation unless the perl module Net::CIDR is installed.  You
  # may repeat the allow line as many times as you'd like

  allow ^127\.0\.0\.1$
  allow ^::1$

  # If you have installed the Net::CIDR perl module, you can use one or more
  # cidr_allow and cidr_deny address/mask patterns.  A connecting client must
  # match any cidr_allow, and not match any cidr_deny.  Note that a netmask
  # *must* be provided, even if it's /32
  #
  # Example:
  #
  # cidr_allow 127.0.0.1/32
  # cidr_allow 192.0.2.0/24
  # cidr_deny  192.0.2.42/32

  # Which address to bind to;
  host *
  # host 127.0.0.1

  # And which port
  port 4949


SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin-node`, :ref:`munin-run`
