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
   to colour the graphs. The "default" palete has more colours and
   better contrast than the "old" palette.

   Affects: :ref:`munin-graph`

.. option:: custom_palette rrggbb rrggbb ...

   The user defined custom palette used by :ref:`munin-graph` and :ref:`munin-cgi-graph`
   to colour the graphs. This option override existing palette.
   The palette must be space-separeted 24-bit hex color code.

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

.. index::
   pair: example; munin.conf

EXAMPLE
=======

A minimal configuration file

::

  [client.example.com]
    address client.example.com
