.. _advanced-plugin-dev:

======================================
Advanced Topics for Plugin Development
======================================

When developing plugins for Munin, there are some guidelines that should be observed.


Error Handling
==============

Munin plugins should handle error conditions in a fashion that make them easy to understand and debug.  Use these
guidelines when developing a plugin:

* Output may always contain comments.  Use comment blocks (lines starting with `#`) within the output to give more information
* If an error occurs in the plugin, two things should happen:

 * A non-zero exit code must be issued
 * A descriptive message should be written to STDERR.  On a deployed plugin, this message will appear in munin-node.log.  When invoked via munin-run, it'll appear in the console.


.. _plugin-field-thresholds:

Field thresholds (warning and critical)
=======================================

The :ref:`.warning <fieldname.warning>` and :ref:`.critical <fieldname.critical>` attributes are
used to detect unwanted situations, e.g. a disk being almost full.

Some plugins may want to supply default thresholds, while allowing these values to be overridden by
the user.

Munin's plugin modules for Perl and Shell provide helper functions for this purpose. They allow the
user to override the plugin's thresholds via the environment variables ``FIELDNAME_warning`` or
``warning`` (likewise for "critical") in :ref:`munin.conf <munin.conf>`.


Example shell plugin
--------------------

::

  ...

  . "$MUNIN_LIBDIR/plugins/plugin.sh"

  ...

  warning=${warning:-0.80} critical=${critical:-0.95} print_thresholds "$fieldname"

  ...


Example perl plugin
-------------------

::

  ...

  use Munin::Plugin;

  ...

  print_thresholds("$fieldname", undef, undef, 0.80, 0.95);

  ...

See ``man Munin::Plugin`` for details.


Handling temporary files
========================

Munin plugins often run with elevated privileges.

When creating and using temporary files, it is important to ensure that this is done securely.

Example shell plugin
--------------------

.. code-block:: bash

  #!/bin/sh

  # Allow others to override mktemp command with env.mktemp_command in the plugin config
  mktemp_command="${mktemp_command:-/bin/mktemp}"

  # make a temporary file, exit if something goes wrong, and ensure it is removed after exit
  my_tempfile=$(mktemp_command) || exit 73
  trap 'rm -f "$my_tempfile"' EXIT

  # rest of the plugin…

Example perl plugin
-------------------

For perl, you have better tools available to keep data in memory, but if you need a temporary file
or directory, you can use `File::Temp <https://metacpan.org/pod/File::Temp>`_.

.. code-block:: perl

  #!/usr/bin/perl

  use strict;
  use warnings;

  # make a tempfile, it will be removed on plugin exit
  use File::Temp qw/ tempfile /;
  my ($fh, $filename) = tempfile();


Storing the Plugin's State
==========================

Very few plugins need to access state information from previous executions of this plugin itself.
The :ref:`munin-node` prepares the necessary environment for this task. This includes a separate
writable directory that is owned by the user running the plugin and a file that is unique for each
:ref:`master <master-index>` that is requesting data from this plugin. These two storage locations
serve different purposes and are accessible via environment variables:

* :ref:`MUNIN_PLUGSTATE <plugin-env-MUNIN_PLUGSTATE>`: directory to be used for storing files that should be accessed by other plugins
* :ref:`MUNIN_STATEFILE <plugin-env-MUNIN_STATEFILE>`: single state file to be used by a plugin that wants to track its state from the last time it was requested by the same master

.. note::

  The datatype :ref:`DERIVE <datatype_derive>` is an elegant alternative to using a state file for
  tracking the *rate of change* of a given numeric value.


Portability
===========

Plugins should run on a wide variety of platforms.

Shell Plugins
-------------

Please prefer `/bin/sh` over `/bin/bash` (or other shells) if you do not need advanced features (e.g. arrays).
This allows such plugins to run on embedded platforms and some \*BSD systems that do not contain advanced shells by default.
When using `/bin/sh` as the interpreter, a feature set similar to busybox's `ash` or Debian's `dash` can be expected (i.e. use `shellcheck -s dash PLUGIN` for code quality checks).

The availability of the following tools can be assumed:

  * all the goodies within `coreutils <https://www.gnu.org/software/coreutils>`_
  * awk (e.g. `gawk <https://www.gnu.org/software/gawk>`_)

    * it is recommended to stick to the POSIX set of features (verify via `POSIXLY_CORRECT=1; export POSIXLY_CORRECT`)

  * `find <https://www.gnu.org/software/findutils>`_
  * `grep <https://www.gnu.org/software/grep>`_
  * `sed <https://www.gnu.org/software/sed>`_

In order to avoid external tools (e.g. `bc` or `dc`), the shell's arithmetic substitution (e.g. `a=$((b + 3))`) should be used for integer operations and `awk` (e.g. `awk '{print $1/1000}'`) for non-trivial calculations.

Python Plugins
--------------

Python2 is approaching its end-of-life in 2020 and Python3 was released 2008. Thus new plugins should be written in Python3 only.

Core modules (included in CPython) should be preferred over external modules, whenever possible (e.g. use `urllib <https://docs.python.org/3/library/urllib>`_ instead of `requests <http://python-requests.org>`_).


Remote Monitoring
=================

Remote monitoring plugins are plugins that run on one node, but collect metrics from a different node. They are typically used to collect metrics from systems that can't have munin-node installed on them directly, but still export useful metrics over the network (via, e.g., SNMP or HTTP). SNMP is the most common protocol used for these plugins; for details on using SNMP specifically, including the ``Munin::Plugin::SNMP`` module, see :ref:`HOWTO write SNMP plugins <howto-write-snmp-plugins>`.

Naming
------

Remote monitoring plugins should use the naming format ``[protocol]__[metric]``, or ``[protocol]__[metric]_`` for remote wildcard plugins, e.g. ``snmp__uptime`` or ``snmp__if_`` -- note the double underscore. When instantiated the name of the host to monitor will go between those underscores, e.g. ``snmp_printserver_uptime`` or ``snmp_gateway_if_eth0``.

``config``
----------

The plugin should figure out the name of the host being monitored by inspecting its own filename, e.g. ``HOST=$(basename "$0" | cut -d_ -f2)``. If that's ``localhost``, it should behave like any other (non-remote) plugin; otherwise it should emit ``host_name $HOST`` before any other configuration data. This lets the node know which plugins collect local metrics and which ones collect metrics from remote hosts -- and, for the latter, which hosts they collect from.

``fetch``
---------

Nothing special is needed here! Figure out ``$HOST`` as above, then fetch metrics for it and emit them like any other plugin.

``munin.conf``
--------------

Specify the host as normal, but set ``use_node_name no``, and set ``address`` to the address of the node the remote monitoring plugins run on, not the address of the host being monitored. For example, if you have some networking gear, ``gate1`` and ``gate2``, monitored via SNMP by the node on ``netmon``, you would write something like:

::

  [network;gate1]
  use_node_name no
  address netmon

  [network;gate2]
  use_node_name no
  address netmon
