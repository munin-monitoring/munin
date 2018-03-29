.. _plugin-bcp:

==============================================
 Best Current Practices for good plugin graphs
==============================================

.. index::
   pair: contributing; plugin; best current practices

These are some guidelines that will make it easier to understand the graphs produced by your plugins.

Graph labeling
==============

* The different labels should be short enough to fit the graph
* The label should be specific: "transaction volume" is better than "volume", "5 min load average" is better than "load average".
* If the measure is a rate the time unit should be given in the vertical label: "bytes / ${graph_period}" is better than "bytes" or the even worse "throughput".
* All the ``graph_*`` values specified by the plugin can be used in the title and vlabel values.

``${graph_*}`` in plugin output will be magically replaced with the correct value by Munin.

This is a good example of all this: `exim_mailstats <http://munin.ping.uio.no/ping.uio.no/pike.ping.uio.no/exim_mailstats.html>`_

Values
======

Plugins that measure rates should strive to use absolute counters (COUNTER, DERIVE) rather than averages (GAUGE) calculated by an OS tool. E.g. ``iostat`` on Solaris or ``ifconfig`` (:ref:`see the demonstration plugin <network-interface-plugin>`) will output counters rather than short term averages. Counters will be much more correct since Munin can average the measure over its own sample interval instead
- this will for example pick up short peaks in loads that Munin might otherwise not see.

DERIVE vs. COUNTER
------------------

To avoid spikes in the graph when counters are reset (as opposed to wrapping), use :ref:`${name}.type <fieldname.type>` DERIVE and :ref:`${name}.min <fieldname.min>` 0. Note that this will cause lost data points when the counter wraps, and should therefore not be used with plugins that are expected to wrap more often than be reset (or sampled). An example of this is the Linux ``if_`` plugin on 32bit machines with a busy (100Mbps) network.

The reasons behind this is rooted in the nature of 32 bit two's complement arithmetic and the way such numbers wrap around from huge positive numbers to huge negative numbers when they overflow.  Please refer to these two articles in wikipedia to learn more: `Binary Arithmetic <http://en.wikipedia.org/wiki/Binary_arithmetic>`_ and `Two's complement <http://en.wikipedia.org/wiki/Two%27s_complement>`_.

To summarize:
 #. Use DERIVE
 #. Use :ref:`${name}.min <fieldname.min>` to avoid negative spikes

.. _plugin-bcp-graphscaling:

Graph scaling
=============

::

 graph_args --base 1000 --lower-limit 0
 graph_scale no

See :ref:`graph_args <example-graph-args>` for its documentation.

Choosing a scaler:
 * For disk bytes use 1024 as base (df and other Unix tools still use this though disks are sold assuming 1K=1000)
 * For RAM bytes use 1024 as base (RAM is sold that way and always accounted for that way)
 * For network bits or bytes use 1000 as base (ethernet and line vendors use this)
 * For anything else use 1000 as base

The key is to choose the base that people are used to dealing with the units in.  Of the four points above, what units to use for disk storage is most in doubt: the sale of disks the last 10-15 years with 1K=1000 and the recent addition of ``--si`` options to GNU tools tell us that people are starting to think of disks that way too. But 1024 is ''very'' basic to the design of disks and filesystems on a low level so the 1024 is likely to remain.

In addition, most people want to see network speeds in bits not bytes.  If your readings are in bytes you might multiply the number by 8 yourself to get bits, or you may leave it to Munin (actually rrd).  If the throughput number is reported in ``down.value`` the ``config`` output may specify ``down.cdef down,8,*`` to multiply the down number by 8 (this syntax is known as Reverse Polish Notation).

.. _plugin-bcp-direction:

Direction
=========

For a rate measurement plugin that can report on data both going in and out, such as the if_("eth0") plugin that would report on bytes (or packets) going in and out, it makes sense to graph incoming and outgoing on the same graph.  The convention in Munin has become that outgoing data is graphed above the x-axis (i.e., positive) and incoming data is graphed below the y-axis like this:

.. image:: graphs/if_eth0-week.png

This is achieved by using the following field attributes.  This example assumes that your plugin generates two fieldnames ``inputrate`` and ``outputrate``.  The input rate goes under the x-axis so it needs to be manipulated:

::

 inputrate.graph no
 outputrate.negative inputrate

The first disables normal graphing of inputrate.  The second activates a hack in munin to get the input and output graphs in the same color and on opposite sides of the x-axis.

Legends
=======

As of version 1.2 Munin supports explanatory legends on both the graph and field level.  Many plugins - even the CPU use plugin - should make use of this. The CPU "io wait" number for example will only get larger than 0 if the CPU has nothing else to do in the time interval.  Many (nice) graphs will only be completely clear once a rather obscure man page has been read (or in the Linux case perhaps even the kernel source).  Using the legend possibilities Munin supports will help this.

Graph legends are added by using the :ref:`graph_info <graph_info>` attribute, while field legends use the :ref:`fieldname.info <fieldname.info>` attribute.

Graph category
==============

If the plugin gives the :ref:`graph_category <graph_category>` attribute in its :ref:`config <plugin-config>` output, the graph will be grouped together with other graphs of the same category.  Please consult the :ref:`well-known categories <well-known-categories>` for a list of the categories currently in use.

Legal characters
================

The legal characters in a field name are documented in :ref:`Notes on field names <notes-on-fieldnames>`

Documentation
=============

Extended documentation should be added within the documentation header of the plugin script. See our `instructions on POD style documentation <http://munin-monitoring.org/wiki/munindoc>`_ in the wiki.


Error Handling
==============

Munin plugins should handle error conditions in a fashion that make them easy to understand and debug.  Use these
guidelines when developing a plugin:

* Output may always contain comments.  Use comment blocks (lines starting with `#`) within the output to give more information
* If an error occurs in the plugin, two things should happen:

 * A non-zero exit code must be issued
 * A descriptive message should be written to STDERR.  On a deployed plugin, this message will appear in munin-node.log.  When invoked via munin-run, it'll appear in the console.


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
  * `sed <https://www.gnu.org/software/sed>`_
  * awk (e.g. `gawk <https://www.gnu.org/software/gawk>`_)

    * you should stick to the POSIX set of features (verify via `POSIXLY_CORRECT=1; export POSIXLY_CORRECT`)

In order to avoid external tools (e.g. `bc` or `dc`), the shell's arithmetic substition (e.g. `a=$((b + 3))`) should be used for integer operations and `awk` (e.g. `awk '{print $1/1000}'`) for non-trivial calculations.

Python Plugins
--------------

Python2 is approaching its end-of-life in 2020 and Python3 was released 2008. Thus new plugins should be written in Python3 only.

Core modules (included in CPython) should be prefered over external modules, whenever possible (e.g. use `urllib <https://docs.python.org/3/library/urllib>`_ instead of `requests <http://python-requests.org>`_).
