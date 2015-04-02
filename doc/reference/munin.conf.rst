
.. _munin.conf:

.. program:: munin.conf

============
 munin.conf
============

DESCRIPTION
===========

This is the configuration file for the munin master. It is used by
:ref:`munin-update`, :ref:`munin-graph`, :ref:`munin-limits`.
:ref:`munin-html`.

.. _master-conf-global-directives:

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
   :ref:`munin-httpd` to generate HTML pages. Default
   /etc/munin/templates

.. option:: fork <yes|no>

   This directive determines whether :ref:`munin-update` fork when
   gathering information from nodes. Default is "yes".

   If you set it to "no" munin-update will collect data from the nodes
   in sequence. This will take more time, but use less resources. Not
   recommended unless you have only a handful of nodes.

   Affects: :ref:`munin-update`

.. option:: timeout <seconds>

   This directive determines how long :ref:`munin-update` allows a worker to
   fetch data from a single node.  Default is "180".

   Affects: :ref:`munin-update`

.. option:: palette <default|old>

   The palette used by :ref:`munin-graph` and :ref:`munin-httpd`
   to color the graphs. The "default" palette has more colors and
   better contrast than the "old" palette.

   Affects: :ref:`munin-graph`

.. option:: custom_palette rrggbb rrggbb ...

   The user defined custom palette used by :ref:`munin-graph` and
   :ref:`munin-httpd` to color the graphs. This option override
   existing palette.  The palette must be space-separated 24-bit hex
   color code.

   Affects: :ref:`munin-graph`
   
.. option:: graph_data_size <normal|huge>

   This directive sets the resolution of the RRD files that are
   created by :ref:`munin-graph` and :ref:`munin-httpd`.

   Default is "normal".

   "huge" saves the complete data with 5 minute resolution for 400
   days.

   Changing this directive has no effect on existing graphs

   Affects: :ref:`munin-graph`

.. option:: graph_strategy <cgi|cron>

   If set to "cron", :ref:`munin-graph` will graph all services on all
   nodes every run interval.

   If set to "cgi", :ref:`munin-graph` will do nothing. This is the
   proper setting when you run :ref:`munin-httpd`.

   Affects: :ref:`munin-graph`

.. option:: html_strategy <strategy>

   Valid strategies are "cgi" and "cron". Default is "cgi".

   If set to "cron", :ref:`munin-html` will recreate all html pages
   every run interval.

   If set to "cgi", :ref:`munin-html` will do nothing.  This is the
   proper setting when you run :ref:`munin-httpd`.

.. _directive-contact:

.. option:: contact.<contact name>.command <command>

   Define which contact command to run.

.. option:: contact.<contact name>.text <text>

   Text to pipe into the command.

.. option:: contact.<contact name>.max_messages <number>

   Close (and reopen) command after given number of messages. E.g. if set to 1 for an email target,
   Munin sends 1 email for each warning/critical. Useful when relaying messages to external processes
   that may handle a limited number of simultaneous warnings.

.. index::
   pair: example; munin.conf

NODE DEFINITIONS
================

Node definitions can have several types. In all forms, the definition is used to generate the node
name and group for the node, and the following lines define its directives. All following directives
apply to that node until another node definition or EOF.

When defining a nodename it is vital that you use a standard DNS name, as in, one that uses only
"a-z", "-", and ".". While other characters can be used in a DNS name, it is against the RFC, and
Munin uses the other characters as delimiters. If they appear in nodenames, unexpected behavior may
occur.

The simplest node definition defines the section for a new node by simply wrapping the DNS name of
the node in brackets, e.g. ``[machine1.example.com]``. This will add the node *machine1.example.com*
to the group *example.com*.

The next form of definition is used to define the node and group explicitly. It follows the form
``[example.com;machine1.sub.example.com]``. This adds the node *machine1.sub.example.com* to the
group *example.com*. This can be useful if you have machines you want to put together as a group
that are under different domains (as in the given example). This can also solve a problem if your
machine is *example.com*, where having a group of *com* makes little sense.

A deeper hierarchy can be specified by using a list of groups, separated with ";". For example:
``[site1;customer2;production;mail.customer2.example.org]``.


NODE DIRECTIVES
---------------

These are directives that can follow a node definition and will apply
only to that node.

.. option:: address <value>

   The host name, IP address, or alternate transport used to contact the node.

   Alternate transport is specified with:

   ``ssh://<address>/<command> <command line arguments>``

   See also :ref:`example-alternate-transport`.

.. option:: port <port number>

   The port number of the node. Ignored if using alternate transport. Default is "4949".

.. option:: local_address <address>

   The local address to connect to the node from. This overrides a group or global directive.

.. option:: use_node_name <yes|no>

   Overrides the name supplied by the node. Allowed values: "yes" and "no". Defaults to "no".

.. option:: contacts <no|contact ...>

   A list of contacts used by munin-limits to report values passing the warning and critical
   thresholds.

   If set to something else than "no", names a list of contacts which should be notified for this
   node. Default is "no".

.. option:: notify_alias <node name>

   Used by :ref:`munin-limits`.

   If set, changes the name by which the node presents itself when warning through munin-limits.

.. option:: ignore_unknown <yes|no>

   If set, ignore any unknown values reported by the node. Allowed values are "yes"
   and "no". Defaults to "no".

   Useful when a node is expected to be off-line frequently.

.. option:: update <yes|no>

   Fetch data from this node with :ref:`munin-update`? Allowed values are "yes" and "no". Defaults
   to "yes".

   If you make a virtual node which borrow data from real nodes for aggregate graphs, set this to
   "no" for that node.

PLUGIN DIRECTIVES
-----------------

These directives follow a node definition and are of the form "plugin.directive <value>".

Using these directives you can override various directives for a plugin, such as its contacts, and
can also be used to create graphs containing data from other plugins.

.. _master-conf-field-directives:

FIELD DIRECTIVES
----------------

These directives follow a node definition and are of the form "plugin.field <value>".

Using these directives you can override values originally set by plugins on the nodes, such as
warning and critical levels or graph names.

.. option:: graph_height <value>

   The graph height for a specific service. Default is 175. Affects: :ref:`munin-graph`.

.. option:: graph_width <value>

   The graph width for a specific service. Default is 400. Affects: :ref:`munin-graph`.

.. option:: warning <value>

   The value at which munin-limits will mark the service as being in a warning state. Value can be a
   single number to specify a limit that must be passed or they can be a comma separated pair of
   numbers defining a valid range of values. Affects: :ref:`munin-limits`.

.. option:: critical <value>

   The value at which munin-limits will mark the service as being in a critical state. Value can be
   a single number to specify a limit that must be passed or they can be a comma separated pair of
   numbers defining a valid range of values Affects: :ref:`munin-limits`.

EXAMPLES
========

Three nodes
-----------

A minimal configuration file, using default settings for everything, and specifying three nodes.

::

  [mail.example.com]
    address mail.example.com

  [web.example.com]
    address web.example.com

  [munin.example.com]
    address localhost

Virtual node
------------

A virtual node definition. Disable update, and make a graph consisting of data from other graphs.

::

  [example.com;Totals]
    update no
    load.graph_title Total load
	load.sum_load.label load
	load.sum_load.special_stack mail=mail.example.com web=web.example.com munin=munin.example.com

.. _example-alternate-transport:

Alternate transport
-------------------

Connect to munin-nodes on a remote site, through a bastion host, using ssh.

::

  [mail.site2.example.org]
    address ssh://bastion.site2.example.org/bin/nc mail.site2.example.org 4949

  [www.site2.example.org]
    address ssh://bastion.site2.example.org/bin/nc www.site2.example.org 4949

SEE ALSO
========

See :ref:`munin` for an overview over munin.

