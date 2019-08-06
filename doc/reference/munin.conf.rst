.. _munin.conf:

.. program:: munin.conf

============
 munin.conf
============

DESCRIPTION
===========

This is the configuration file for the munin master. It is used by
:ref:`munin-update`, :ref:`munin-graph`, :ref:`munin-limits`.
:ref:`munin-html`, :ref:`munin-cgi-graph` and :ref:`munin-cgi-html`.

GLOBAL DIRECTIVES
=================

Global directives affect all munin master components unless specified
otherwise.

.. option:: dbdir <path>

   The directory where munin stores its database files. Default:
   /var/lib/munin

.. option:: logdir <path>

   The directory where munin stores its logfiles. Default:
   /var/log/munin

.. option:: htmldir <path>

   The directory where :ref:`munin-html` stores generated HTML pages,
   and where :ref:`munin-graph` stores graphs. Default:
   /var/cache/munin/www

.. option:: rundir <path>

   Directory for files tracking munin's current running state.
   Default: /var/run/munin

.. option:: tmpldir <path>

   Directories for templates used by :ref:`munin-html` and
   :ref:`munin-cgi-html` to generate HTML pages. Default
   /etc/munin/templates

.. option:: fork <yes|no>

   This directive determines whether :ref:`munin-update` fork when
   gathering information from nodes. Default is "yes".

   If you set it to "no" munin-update will collect data from the nodes
   in sequence. This will take more time, but use less resources. Not
   recommended unless you have only a handful of nodes.

   Affects: :ref:`munin-update`

.. option:: palette <default|old>

   The palette used by :ref:`munin-graph` and :ref:`munin-cgi-graph`
   to colour the graphs. The "default" palette has more colours and
   better contrast than the "old" palette.

   Affects: :ref:`munin-graph`

.. option:: graph_data_size <normal|huge>

   This directive sets the resolution of the RRD files that are
   created by :ref:`munin-graph` and :ref:`munin-cgi-graph`.

   Default is "normal".

   "huge" saves the complete data with 5 minute resolution for 400
   days.

   Changing this directive has no effect on existing graphs

   Affects: :ref:`munin-graph`

.. option:: graph_strategy <cgi|cron>

   If set to "cron", :ref:`munin-graph` will graph all services on all
   nodes every run interval.

   If set to "cgi", :ref:`munin-graph` will do nothing. To generate
   graphs you must then configure a web server to run
   :ref:`munin-cgi-graph` instead.

   Affects: :ref:`munin-graph`

.. option:: html_strategy <strategy>

   Valid strategies are "cgi" and "cron". Default is "cgi".

   If set to "cron", :ref:`munin-html` will recreate all html pages
   every run interval.

   If set to "cgi", :ref:`munin-html` will do nothing. To generate
   html pages you must configure a web server to run
   :ref:`munin-cgi-graph` instead.

.. option:: ssh_command <command>

   The name of the secure shell command to use.  Can be fully
   qualified or looked up in $PATH.

   Defaults to "ssh".

.. option:: ssh_options <options>

   The options for the secure shell command.

   Defaults are "-o ChallengeResponseAuthentication=no -o
   StrictHostKeyChecking=no".  Please adjust this according to your
   desired security level.

   With the defaults, the master will accept and store the node ssh
   host keys with the first connection. If a host ever changes its ssh
   host keys, you will need to manually remove the old host key from
   the ssh known hosts file. (with: ssh-keygen -R <node-hostname>, as
   well as ssh-keygen -R <node-ip-address>)

   You can remove "StrictHostKeyChecking=no" to increase security, but
   you will have to manually manage the known hosts file.  Do so by
   running "ssh <node-hostname>" manually as the munin user, for each
   node, and accept the ssh host keys.

   If you would like the master to accept all node host keys, even
   when they change, use the options "-o
   UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o
   PreferredAuthentications=publickey".

.. index::
   pair: example; munin.conf

EXAMPLE
=======

A minimal configuration file

::

  [client.example.com]
    address client.example.com
