.. program:: munin.conf
.. index::
   pair: virtual; node

.. _munin.conf:

============
 munin.conf
============

DESCRIPTION
===========

This is the configuration file for the munin master. It is used by :ref:`munin-update`, :ref:`munin-limits` and :ref:`munin-httpd`.

Location in packages is usually ``/etc/munin/`` while if compiled from source it is often found in ``/etc/opt/munin/``.

The structure is:

#. One general/global section
#. Zero or more group section(s)
#. One or more host section(s)

Group and host sections are defined by declaring the group or host name in brackets. Everything under a section definition belongs to that section, until a new group or host section is defined.

.. note::

        As **the global section** is not defined through brackets, it **must be found prior to any group or host sections**.
        It will not work if you place them in later sections of the config file.
        We recommend to use the delivered munin.conf file and adapt it to your needs.


.. _master-conf-global-directives:

GLOBAL DIRECTIVES
=================

Global directives affect all munin master components unless specified
otherwise.

.. option:: dbdir <path>

   The directory where munin stores its database files (Default: ``/var/lib/munin``).
   It must be writable for the user running :ref:`munin-cron`.
   RRD files are placed in subdirectories *$dbdir/$domain/*

.. option:: htmldir <path>

   The directory shown by :ref:`munin-httpd`. It must be writable for the user running :ref:`munin-httpd`.
   For munin 2.0: The directory where :ref:`munin-html` stores generated HTML pages, and where :ref:`munin-graph` stores graphs.

.. option:: logdir <path>

   The directory where munin stores its logfiles (Default: ``/var/log/munin``).
   It must be writable by the user running munin-cron.

.. option:: rundir <path>

   Directory for files tracking munin's current running state. Default: ``/var/run/munin``

.. option:: tmpldir <path>

   Directories for templates used by :ref:`munin-httpd` (munin 2.0: :ref:`munin-html`) to generate HTML pages.
   Default ``/etc/munin/templates``

.. option:: staticdir <path>

   Where to look for the static www files.

.. option:: cgitmpdir <path>

   Temporary cgi files are here. It has to be writable by the cgi user (For Munin stable 2.0 usually ``nobody`` or ``httpd``).

.. option:: includedir <path>

   (Exactly one) directory to include all files from.
   Default ``/etc/munin/plugin-conf.d/``

.. option:: local_address <address>

   Sets the local IP address that `munin-update` should bind to when contacting the nodes.
   May be used several times (one line each) on a multi-homed host.
   Should default to the most appropriate interface, based on routing decision.

.. note:: This directive can be overwritten via settings on lower hierarchy levels (group, node).

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

   The palette used by :ref:`munin-httpd` to color the graphs. The
   "default" palette has more colors and better contrast than the
   "old" palette.

.. option:: custom_palette rrggbb rrggbb ...

   The user defined custom palette used by :ref:`munin-httpd` to color
   the graphs. This option overrides the existing palette.  The
   palette must be space-separated 24-bit hex color code.

.. option:: graph_period <second>

   You can choose the time reference for "DERIVE" like graphs, and show
   "per minute" => ``minute``, "per hour" => ``hour`` values instead of the default "per second".

.. option:: html_dynamic_images 1

   Munin HTML templates use this variable to decide whether to use dynamic
   ("lazy") loading of images with javascript so that images are loaded as they
   are scrolled in view. This prevents excessive load on the web server.
   Default is 0 (off).

.. option:: max_graph_jobs 6

   Available since Munin 1.4.0. Maximum number of parallel processes used by
   `munin-graph <http://guide.munin-monitoring.org/en/stable-2.0/reference/munin-graph.html#munin-graph>`_
   when calling `rrdgraph <https://oss.oetiker.ch/rrdtool/doc/rrdgraph.en.html>`_.
   The optimal number is very hard to guess and depends on the number of cores of CPU, the I/O bandwidth available,
   if you have SCSI or (S)ATA disks and so on. You will need to experiment. Set on the command line with the ``-n n`` option.
   Set to 0 for no forking.

.. option:: munin_cgi_graph_jobs 6

   munin-cgi-graph is invoked by the web server up to very many times at the
   same time.  This is not optimal since it results in high CPU and memory
   consumption to the degree that the system can thrash.  Again the default is 6.
   Most likely the optimal number for ``max_cgi_graph_jobs`` is the same as ``max_graph_jobs``.

.. option:: cgiurl_graph /munin-cgi/munin-cgi-graph

   If the automatic CGI url is wrong for your system override it here.

.. option:: max_size_x 4000

   The max width of images in pixel. Default is 4000.
   Do not make it too large otherwise RRD might use all RAM to generate the images.

.. option:: max_size_y 4000

   The max height of images in pixel. Default is 4000.
   Do not make it too large otherwise RRD might use all RAM to generate the images.

.. option:: graph_strategy <cgi|cron>

   This option is available only in munin 2.0.
   In munin 2.0 graphics files are generated either via cron or by a CGI process.

   If set to "cron", :ref:`munin-graph` will graph all services on all
   nodes every run interval.

   If set to "cgi", :ref:`munin-graph` will do nothing.
   Instead graphs are generated by the webserver on demand.

.. option:: html_strategy <cgi|cron>

   This option is available only in munin 2.0.
   In munin 2.0 HTML files are generated either via cron (default) or by a CGI process.

   If set to "cron", :ref:`munin-html` will recreate all html pages
   every run interval.

   If set to "cgi", :ref:`munin-html` will do nothing.
   Instead HTML files are generated by the webserver on demand.
   This setting implies ``graph_strategy cgi``

.. option:: max_processes 16

   `munin-update` runs in parallel.

   The default max number of processes is 16, and is probably ok for you.
   Should be not higher than 4 x CPU cores.

   If set too high, it might hit some process/ram/filedesc limits.
   If set too low, munin-update might take more than 5 min.
   If you want munin-update to not be parallel set it to 1.

.. option:: rrdcached_socket /var/run/rrdcached.sock

   RRD updates are per default, performed directly on the rrd files.
   To reduce IO and enable the use of the rrdcached, uncomment it and set it to the location of the socket that rrdcached uses.

.. _graph_data_size:

.. option:: graph_data_size <normal|huge|custom>

   This directive sets the resolution of the RRD files that are
   created by :ref:`munin-update`.

   Default is "normal".

   "huge" saves the complete data with 5 minute resolution for 400 days.

   With "custom" you can define your own resolution. See :ref:`the instruction on custom RRD sizing <custom-rrd-sizing>` for the details.

   Changing this directive has no effect on existing graphs

.. _directive-contact:

.. option:: contact.your_contact_name.command <command>

   Define which contact command to run. See the tutorial :ref:`Let Munin croak alarm <tutorial-alert>` for detailed instruction about the configuration.

.. option:: contact.your_contact_name.text <text>

   Text to pipe into the command.

.. option:: contact.your_contact_name.max_messages <number>

   Close (and reopen) command after given number of messages. E.g. if set to 1 for an email target,
   Munin sends 1 email for each warning/critical. Useful when relaying messages to external processes
   that may handle a limited number of simultaneous warnings.

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

.. option:: domain_order <group1> <group2> ..

   Change the order of domains/groups. Default: Alphabetically sorted

GROUP DIRECTIVES
================

If you want to set directives on the group level you have to start the group section with
the groups name in square brackets.

::

  [mygroup.mydomain]

.. option:: node_order <node1> <node2> ..

   Changes the order of nodes in a domain.
   Default: Alphabetically sorted.

.. option:: contacts <no|your_contact_name1 your_contact_name2 ...>

   A list of contacts used by :ref:`munin-limits` to report values passing the warning and critical thresholds.

   If set to something else than "no", names a list of contacts which should be notified for this node.
   Default is "no" and then **all** defined contacts will get informed when values go over or below thresholds.

.. note:: This directive can be overwritten via settings on lower levels of the hierarchy (node, plugin).


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


.. _master-conf-node-directives:

NODE DIRECTIVES
---------------

These are directives that can follow a node definition and will apply
only to that node.

.. option:: address <value>

   Specifies the host name or IP address, with an optional scheme.

   Permitted schemes are "munin://", "ssh://" or "cmd://".  If no
   scheme is specified, the default is "munin://"

   The "ssh://" and "cmd://" schemes take arguments after the URL.
   See :ref:`address-schemes` for examples.

.. option:: port <port number>

   The port number of the node. Ignored if using alternate transport. Default is "4949".

.. option:: use_node_name <yes|no>

   Overrides the name supplied by the node. Allowed values: "yes" and "no". Defaults to "no".

.. option:: notify_alias <node name>

   Used by :ref:`munin-limits`.

   If set, changes the name by which the node presents itself when warning through :ref:`munin-limits`.

.. note:: This directive can also be used on hiearchy level plugin to change the name by which the plugin presents itself when warning through ``munin-limits``.

.. option:: ignore_unknown <yes|no>

   If set, ignore any unknown values reported by the node. Allowed values are "yes"
   and "no". Defaults to "no".

   Useful when a node is expected to be off-line frequently.

.. option:: update <yes|no>

   Fetch data from this node with :ref:`munin-update`? Allowed values are "yes" and "no". Defaults
   to "yes".

   If you make a virtual node which borrow data from real nodes for aggregate graphs, set this to
   "no" for that node.

.. _master-conf-plugin-directives:

PLUGIN DIRECTIVES
-----------------

These directives follow a node definition and are of the form "plugin.directive <value>".

Using these directives you can override various directives for a plugin, such as its contacts, and
can also be used to create graphs containing data from other plugins.

.. option:: graph_height <value>

   The graph height for a specific service. Default is 200.

   Affects: :ref:`munin-httpd`.

.. option:: graph_width <value>

   The graph width for a specific service. Default is 400.

   Affects: :ref:`munin-httpd`.

For a complete list see the reference of :ref:`global plugin attributes <plugin_attributes_global>`.

.. _master-conf-field-directives:

FIELD DIRECTIVES
----------------

These directives follow a node definition and are of the form "plugin.field <value>".

Using these directives you can override values originally set by plugins on the nodes, such as
warning and critical levels or graph names.

.. option:: warning <value>

   The value at which munin-limits will mark the service as being in a warning state. Value can be a
   single number to specify a limit that must be passed or they can be a comma separated pair of
   numbers defining a valid range of values.

   Affects: :ref:`munin-limits`.

.. option:: critical <value>

   The value at which munin-limits will mark the service as being in a critical state. Value can be
   a single number to specify a limit that must be passed or they can be a comma separated pair of
   numbers defining a valid range of values.

   Affects: :ref:`munin-limits`.

For a complete list see the reference of :ref:`plugin data source attributes <plugin_attributes_data>`.

.. index::
   pair: example; munin.conf

EXAMPLES
========

Three nodes
-----------

A minimal configuration file, using default settings for everything, and specifying three nodes.

.. code-block:: ini

  [mail.example.com]
  address mail.example.com

  [web.example.com]
  address web.example.com

  [munin.example.com]
  address localhost

Virtual node
------------

A virtual node definition. Disable update, and make a graph consisting of data from other graphs.

.. code-block:: ini

   [example.com;Totals]
   update no
   load.graph_title Total load
   load.sum_load.label load
   load.sum_load.special_stack mail=mail.example.com web=web.example.com munin=munin.example.com

.. _address-schemes:

Address schemes
---------------

The scheme tells munin how to connect to munin nodes.

The munin:// scheme is default, if no scheme is specified. By default,
Munin will connect to the munin node with TCP on port 4949.

The following examples are equivalent:

.. code-block:: ini

   # master: /etc/munin/munin.conf.d/node.example.conf
   [mail.site2.example.org]
   address munin://mail.site2.example.org

   [mail.site2.example.org]
   address munin://mail.site2.example.org:4949

   [mail.site2.example.org]
   address mail.site2.example.org

   [mail.site2.example.org]
   address mail.site2.example.org
   port    4949


To connect to a munin node through a shell command, use the "cmd://"
prefix.

.. code-block:: ini

   # master: /etc/munin/munin.conf.d/node.example.conf
   [mail.site2.example.org]
   address cmd:///usr/bin/munin-async [...]

To connect through ssh, use the "ssh://" prefix.

.. code-block:: ini

   # master: /etc/munin/munin.conf.d/node.example.conf
   [mail.site2.example.org]
   address ssh://bastion.site2.example.org/bin/nc mail.site2.example.org 4949

   [www.site2.example.org]
   address ssh://bastion.site2.example.org/bin/nc www.site2.example.org 4949

.. note::

   When using the ssh\:// transport, you can configure how ssh behaves
   by editing `~munin/.ssh/config`.  See the :ref:`ssh transport
   configuration examples <example-transport-ssh>`.

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`example-transport-ssh`
