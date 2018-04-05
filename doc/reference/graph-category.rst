.. _plugin-graph-category:

=========================
 Plugin graph categories
=========================

.. index::
   single: graph_category
   tuple: graph; category
   tuple: plugin; graph_category


The graph categories should create a general grouping of plugins.

A plugin that outputs a "graph_category" attribute will get the graph
grouped with other plugin graphs using the same category, across all
nodes on the same Munin master.

If a plugin doesn't declare a graph_category in its config output,
the graph is moved to default plugin category *other*.

A graph may only belong to one category.

.. note::

   A :ref:`multigraph plugin <plugin-multigraphing>` may create
   multiple graphs, and may place those in different categories.

To get a clear and concise overview in the Munin web interface
**the list of categories should be small and meaningful**.

Therefore we compiled a list of :ref:`well-known categories <well-known-categories>` (see below).

.. _customizing_plugin_category:

Customizing category names
--------------------------

If you have lots of different types of databases in use, it makes sense
to be more specific, and add a graph_category for each e.g. "oracle", "mysql".

Also graphs in several categories could be moved to a "security" category,
but that may not make sense for everyone.

Or in our example below we add a new category `mem`
to collect graphs that show memory aspects of the machine.

In short: Categories should reflect **your** monitoring perspective
and you can move graphs to other categories or create new category names
by overwriting the ``graph_category`` directives in the concerning
host tree section of the Munin Master configuration
in :ref:`munin.conf <master-conf-plugin-directives>`.

Example configuration
=====================

::

  [munin.example.com]
  address localhost

  # Node specific changes of plugin directives
  memory.graph_category mem
  buddyinfo.graph_category mem
  swap.graph_category mem

.. _well-known-categories:

Well known categories
---------------------

Below we name our well-known graph categories
(as already implemented in the contrib repository) and describe
which data sources are suitable for the different categories.

The list is meant as a proposal to discuss and comment.
You can do so on our munin-users mailing list or by creating a bug report (issue) on github.

Info for plugin contributors
============================

**You should refer to the "well known categories"**
when uploading your plugins to the repository.

The graph categories set for plugins in the repositories are also used
to browse the `Munin Plugin Gallery <http://gallery.munin-monitoring.org/>`_.
They are shown on each index page on the left side with a link to
the concerning category page which lists all plugins with graphs in this category.

Therefore it makes sense to **use generic terms only for the categories**.
This way we make sure that users get significant search results when
looking for a special software product using a search engine.
Specific **product names should be used to name the directories
in the repository**, where you place the plugin.
Their names are shown in the Plugin Gallery as title of the section
where the plugins are listed. This way the search for product names
brings only those Gallery pages as hits, where significant plugins are listed.

**Please do not contribute plugins with product specific category terms**
as the search will then bring **all index pages** as hits, which is
not helpful for the users of the Gallery. It should
operate in an effective way as *Plugin Shop*, so significant
retrieval is an important and critical demand here.

.. note:: **Important!** Please write the config line for plugins category in a concrete string (e.g. ``graph_category memory``). The gallery build script scans for such a line in the plugins source code and needs it. Otherwise (e.g. use of variables) your plugin will only be shown under category "other".

----

:graph_category: **1sec**
:Description: ..
:Examples: ..

----

:graph_category: **antivirus**
:Description: Anti virus tools
:Examples: ..

----

:graph_category: **appserver**
:Description: Application servers
:Examples: ..

----

:graph_category: **auth**
:Description: Authentication servers and services
:Examples: ..

----

:graph_category: **backup**
:Description: All measurements around backup creation
:Examples: ..

----

:graph_category: **chat**
:Description: Messaging servers
:Examples: ..

----

:graph_category: **cloud**
:Description: Cloud providers and cloud components
:Examples: ..


----

:graph_category: **cms**
:Description: Content Management Systems
:Examples: ..

----

:graph_category: **cpu**
:Description: CPU measurements
:Examples: ..

----

:graph_category: **db**
:Description: Database servers
:Examples: MySQL, PosgreSQL, MongoDB, Oracle

----

:graph_category: **devel**
:Description: (Software) Development Tools
:Examples: ..

----

:graph_category: **disk**
:Description: Disk and other storage measurements
:Examples: : used space, free inodes, activity, latency, throughput

----

:graph_category: **dns**
:Description: Domain Name Server
:Examples: ..

----

:graph_category: **filetransfer**
:Description: Filetransfer tools and servers
:Examples: ..

----

:graph_category: **forum**
:Description: Forum applications
:Examples: ..

----

:graph_category: **fs**
:Description: (Network) Filesystem activities, includes also monitoring of distributed storage appliances
:Examples: ..

----

:graph_category: **fw**
:Description: All measurements around network filtering
:Examples: ..

----

:graph_category: **games**
:Description: Game-Server
:Examples: ..

----

:graph_category: **htc**
:Description: High-throughput computing
:Examples: ..

----

:graph_category: **loadbalancer**
:Description: Load balancing and proxy servers..
:Examples: ..

----

:graph_category: **mail**
:Description: Mail throughput, mail queues, etc.
:Examples: Postfix, Exim, Sendmail
:Comment: For monitoring a large mail system, it makes sense to
          override this with configuration on the Munin master, and
          make graph categories for the mail roles you provide. Mail
          Transfer Agent (postfix and exim), Mail Delivery Agent
          (filtering, sorting and storage), Mail Retrieval Agent (imap
          server).

----

:graph_category: **mailinglist**
:Description: Listserver
:Examples: ..

----

:graph_category: **memory**
:Description: All kind of memory measurements. Note that info about memory caching servers is also placed here
:Examples: ..

----

:graph_category: **munin**
:Description: Monitoring the monitoring.. (includes other monitoring servers also)
:Examples: ..

----

:graph_category: **network**
:Description: General networking metrics.
:Examples: interface activity, latency, number of open network connections

----

:graph_category: **other**
:Description: Plugins that address seldom used products. Category /other/ is the default, so if the plugin doesn't declare a category, it is also shown here.
:Examples: ..

----

:graph_category: **printing**
:Description: Monitor printers and print jobs
:Examples: ..

----

:graph_category: **processes**
:Description: Process and kernel related measurements
:Examples: ..

----

:graph_category: **radio**
:Description: Receivers, signal quality, recording, ..
:Examples: ..

----

:graph_category: **san**
:Description: Storage Area Network
:Examples: ..

----

:graph_category: **search**
:Description: All kinds of measurement around search engines
:Examples: ..

----

:graph_category: **security**
:Description: Security information
:Examples: login failures, number of pending update packages for OS, number of CVEs
           in the running kernel fixed by the lastest installed
           kernel, firewall counters.

----

:graph_category: **sensors**
:Description: Sensor measurements of device and environment
:Examples: temperature, power, devices health state, humidity, noise, vibration

----

:graph_category: **spamfilter**
:Description: Spam fighters at work
:Examples: ..

----

:graph_category: **streaming**
:Description: ..
:Examples: ..

----

:graph_category: **system**
:Description: General operating system metrics.
:Examples: CPU speed and load, interrupts, uptime, logged in users

----

:graph_category: **time**
:Description: Time synchronization
:Examples: ..

----

:graph_category: **tv**
:Description: Video devices and servers
:Examples: ..

----

:graph_category: **virtualization**
:Description: All kind of measurements about server virtualization. Includes also Operating-system-level virtualization
:Examples: ..

----

:graph_category: **voip**
:Description: Voice over IP servers
:Examples: ..

----

:graph_category: **webserver**
:Description: All kinds of webserver measurements and also for related components
:Examples: requests, bytes, errors, cache hit rate for Apache httpd,
           nginx, lighttpd, varnish, hitch, and other web servers,
           caches or TLS wrappers.

----

:graph_category: **wiki**
:Description: wiki applications
:Examples: ..

----

:graph_category: **wireless**
:Description: ..
:Examples: ..
