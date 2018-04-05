.. _plugin-concise:

======================================
 The Concise guide to plugin authoring
======================================

.. index::
   pair: development; plugin; concise

First of all you should have read :ref:`the HOWTO <howto-write-plugins>`.  This page is an attempt to be brief and yet complete rather than helpful to a beginner.

What is a plugin?
=================

A plugin is a stand-alone program.  In its most common form it is a small perl program or shell script.

The plugins are run by ``munin-node`` and invoked when contacted by the Munin master.  When this happens the ``munin-node`` runs each plugin twice.  Once with the argument ``config`` to get the graph configuration and once with no argument to get the graph data.

Run Time Arguments
==================

A plugin is invoked twice every update-cycle. Once to emit ``config`` information and once to ``fetch`` values.  Please see :ref:`Data exchange between master and node <network-protocol>` for more information about the over-the-wire transactions.

config
------

This argument is mandatory.

The ``config`` output describes the plugin and the graph it creates.  The full set of attributes you can use is found in the :ref:`config reference <plugin-reference>`.

fetch
-----

This argument is mandatory.

When the node receives a ``fetch`` command for a plugin, the plugin is invoked without any arguments on the command line and is expected to emit one or more ``field.value`` attribute values.  One for each thing the plugin observes as defined by the ``config`` output. Plotting of graphs may be disabled by the ``config`` output.

Please note the following about plugin values:

* If the plugin - for any reason - has no value to report, then it may send the value ``U`` for **undefined**.  It *should* report values for every field it has configured during ``config``.
* In 1.3.4 and later: The plugin may back-date values by reporting them on the format ``field.value <epoch>:<value>``, where **<epoch>** is the number of seconds since *1970/1/1 00:00* (unix epoch) and **<value>** is the value in the ordinary way. This can be useful for systems where the plugin receives old data and gives the correct time axis on the graph.

Install Time Arguments
======================

Install time is managed by one utility: :ref:`munin-node-configure <munin-node-configure>`. It can both *auto configure* host plugins and (given the right options) it will *auto configure* snmp plugins for a specific host.

To do this it looks inside the plugins to determine how much *plug-and-play* ability features have been implemented for the user. For details read the :ref:`section about magic markers <magic-markers>`.

An automated installation will run ``munin-node-configure`` and hereby selects the plugins that are ready to run on the specific node. The integration is then done by symlinking them in the service directory (usually ``/etc/munin/plugins``).

Every plugin with a *family=auto* magic marker (``#%# family=auto``) will be interrogated automatically with the ``autoconf`` and perhaps the ``suggest`` methods.  You can change the family list with the ``--families`` option.

Any ``snmp__*`` plugins will be auto configured and installed by ``munin-node-configure --snmp`` with the appropriate arguments.

Every plugin magic marked with *family=snmpauto* and *capabilities=snmpconf* will be interrogated - when appropriately run by ``munin-node-configure``.

.. _plugin-concise-autoconf:

autoconf
--------

A plugin with a *capabilities=autoconf* magic marker will first be invoked with ``autoconf`` as the sole argument.  When invoked thus the plugin should do one of these two:

1. Print "yes" to signal that the plugin thinks it can be useful on this host
2. Print "no" to signal that the plugin does not think so.

The plugin should always exit 0, even if the response is "no".

If the answer was "yes" and it's not a wildcard plugin, the plugin will be linked into the plugins catalog of munin-node.

Example:

::

  # ./load autoconf
  yes


If the answer is "no" the plugin may give a reason in parentheses.  This may help the user to troubleshoot why the plugin is not used/does not work.

::

  # ./load autoconf
  no (No /proc/loadavg)

.. note::

  If a plugin is autoconf-igurable it **SHOULD** not terminate in a uncontrolled way during autoconfiguration. Please make sure that whatever happens it ends up printing a "yes" or a "no" with a reasonable reason for why not.

In particular plugins written in Perl, Python and the like **SHOULD** not require non-core modules without protecting the code section. In perl one would do something like this (from `apache_accesses <https://github.com/munin-monitoring/munin/blob/stable-2.0/plugins/node.d/apache_accesses.in>`_ at the time I write this):

::

  if (! eval "require LWP::UserAgent;") {
      $ret = "LWP::UserAgent not found";
  }
  ...
  if ( defined $ARGV[0] and $ARGV[0] eq "autoconf" ) {
      if ($ret) {
          print "no ($ret)\n";
          exit 0;
      }
  }


If the plugin is to be distributed with Munin the **SHOULDs** above are **MUSTs**.

suggest
-------

Munin creates one graph per plugin. To create many graphs from one plugin, you can write a wildcard plugin.

These plugins take one or more bits of configuration from the file name it is run as. The plugin is stored as one file in the directory for available plugins, but is linked as multiple files in the directory for enabled plugins.  This creates one graph per link name, using just one plugin as source.

Example:

::

  /etc/munin/plugins/if_eth0 -> /usr/share/munin/plugins/if_
  /etc/munin/plugins/if_eth1 -> /usr/share/munin/plugins/if_


As you see: wildcard plugins are easily recognized by their names ending in _.

A wildcard plugin that has a *capabilities=suggest* magic marker will - after ``autoconf`` - be invoked with ``suggest`` as the sole argument. It then should examine the system and determine which of the similar things it can report on and output a list of these.

::

  # ./if_ suggest
  eth0
  eth1

This means that the plugin can be run as ``if_eth0`` and ``if_eth1``. The plugin will then have to examine what's in C is called ``ARGV[0]``, and in perl and shell scripts as ``$0`` to determine what exactly the start command was.

snmpconf
--------

As stated above a plugin magic marked with *family=snmpauto* and *capabilities=snmpconf* will be invoked with ``snmpconf`` as the sole argument. A SNMP plugin is by definition a wildcard plugin, it may examine any host that supports SNMP. The name convention for a SNMP plugin is examplified by the df plugin: ``snmp__df``.  The hostname goes between the two consecutive underlines (_), and when invoked, the plugin may examine ``$0``, as any wildcard plugin must, to determine the name of the host it is to work with. It may also contain two wildcards as in ``snmp__if_``. Here the index of the network interface appears after the third underline (_) at the end of the string. e.g. ``snmp_foo.example.com_if_1``.

On the occasion of being run with ``snmpconf`` the plugin shall output one or more of the following:

For a plugin that is to monitor a number of (enumerated) items: the items have to be counted and indexed in the MIB and the plugin can express this so:

* The word ``number`` followed by a OID giving the number of items
* The word ``index``, followed by a OID ending with a trailing dot on to the table of indices

Both the ``snmp__df`` and the ``snmp__if_`` plugins use this.  The df plugin because it monitors multiple storage resources and wants to monitor only fixed disks. It expresses this by asking for the index OID for storage be present.  The ``snmp__if_`` plugin uses both ``number`` and ``index``.  The number OID gives the number of network interfaces on the device.

For a plugin named in the pattern analogous to ``snmp__if_`` each of the indices will be used at the end of the plugin name, e.g. ``snmp_switch_if_10`` for a device named switch, interface index 10.

* The word ``require`` followed by an OID or the root of an OID that must exist on a SNMP agent. The OID may optionally be followed by a string or RE-pattern that specifies what sort of response is expected.  For a indexed plugin (one that gives "number" and "index" the indecies will be appended to the require OID to check that OID for each indexed item (e.g. a interface)

Example:

::

  # ./snmp__if_ snmpconf
  number  1.3.6.1.2.1.2.1.0
  index   1.3.6.1.2.1.2.2.1.1.
  require 1.3.6.1.2.1.2.2.1.5. [0-9]
  require 1.3.6.1.2.1.2.2.1.10. [0-9]

A require supports any perl RE, so for example one could require (6|32) from a OID to filter out only certain kinds of items.

If all the named items ``require`` and ``number``, ``index`` given are found (and matched if a RE is given) the plugin will be activated by ``munin-node-configure``.

:ref:`munin-node-configure <munin-node-configure>` will send queries to devices that the user has claimed to be interested in, to see if these OIDs exist and have matching values if required. If so the plugin will be linked into the ``munin-node`` service directory (usually ``/etc/munin/plugins``).

Configuration
=============

Plugins are configured through files on each node.

The ``munin-node`` plugin configuration files reside in ``/etc/munin/plugin-conf.d/``.  These are used by ``munin-node`` to determine which privileges a plugin should get (which user and group runs the plugin) and which settings of environment variables should be done for the plugins.  Each file in ``/etc/munin/plugin-conf.d/`` can contain configuration for one or more plugins.

The configuration files are read in alphabetical order and configuration of the last read file overrides earlier configuration.

The format is:

::

  [name or wildcard]
    user <username>
    group <group>
    env.<variable name> <variable content>


Privileges
----------

Munin usually runs each plugin as an unprivileged user.

To run the plugin as a specific user:

::

  [example]
   user someuser

To run a plugin with an additional group:

::

  [example]
   group somegroup

 
Environment variables
---------------------

To set the variable ``logfile`` to ``/var/log/example.log``:

::

  [example]
   env.logfile /var/log/some.log

When using environment variables in your plugins, the plugin should contain sensible defaults.

Example ``/bin/sh`` code.  This adds an environment variable called ``$LOG``, and sets it to the value of ``$logfile`` (from ``env.logfile`` in the Munin plugin configuration), with a default of ``/var/log/syslog`` if ``$logfile`` is empty:

::

  #!/bin/sh

  LOG=${logfile:-/var/log/syslog}


Example configuration
---------------------

This plugin reads from ``/var/log/example.log``, which is readable by user ``root`` and group ``adm``.  We set an environment variable for the logfile, and we need additional privileges to be able to read it.  Choosing the least amount of privileges, we choose to run the plugin with the group ``adm`` instead of user ``root``.

::

  [example]
   group adm
   env.logfile /var/log/example.log


Activating a Munin plugin
-------------------------

To activate a plugin it needs to be executable and present in the munin plugin directory, commonly ``/etc/munin/plugins``.  It can be copied or symlinked here.

Plugins shipped with munin-node are placed in the directory for available Munin plugins, commonly ``/usr/share/munin/plugins``.  To activate these, make symlinks to the Munin plugin directory, commonly ``/etc/munin/plugins``.


Running a Munin plugin interactively
====================================

A munin plugin is often run with modified privileges and with a set of environment variables. To run a plugin within its configured environment, use the :ref:`munin-run` command. It takes a plugins service link name as the first argument and any plugin argument as the next.

Example (with long lines broken):

::

  ssm@mavis:~$ munin-run load config
  graph_title Load average
  graph_args --base 1000 -l 0
  graph_vlabel load
  graph_scale no
  graph_category system
  load.label load
  load.warning 10
  load.critical 120
  graph_info The load average of the machine describes how many processes \
             are in the run-queue (scheduled to run "immediately").
  load.info Average load for the five minutes.

::

  ssm@mavis:~$ munin-run load
  load.value 0.11
