.. _plugin-graph-category:

=========================
 Plugin graph categories
=========================

.. index::
   single: graph_category
   tuple: graph; category
   tuple: plugin; graph_category


.. _plugin_attributes_global:

A plugin that outputs a "graph_category" attribute will get the graph
grouped with other plugin graphs using the same category, across all
nodes on the same munin master.

A graph may only belong to one category.

.. note::

   A :ref:`multigraph plugin <plugin-multigraphing>` may create
   multiple graphs, and may place those in different categories.

To get a clear and concise overview in the Munin web interface, the
list of categories should be small and meaningful.

The graph categories should create a general grouping of plugins. If
you have lots of different types of databases in use, it makes sense
to be more specific, and add a graph_category for each.

Categories may be overridden in the munin configuration, and should
reflect your monitoring perspective.

.. note::

   Depending on your perspective, graphs in several categories below
   could be moved to a "security" category, but that may not make
   sense for everyone.

   To move a graph to another category, add configuration for it on
   the munin master to override what the plugin emits.

Example Categories
==================

Hardware and operating system categories
----------------------------------------

:graph_category: **system**
:Description: Graphs general operating system metrics.
:Examples: CPU speed and load, uptime, number of processes, paging
           activity, open file descriptors.

----

:graph_category: **network**
:Description: Graphs general networking metrics.
:Examples: Network interface activity, latency, number of open network
           connections, firewall counters.

----

:graph_category: **storage**
:Description: A general category for data storage.
:Examples: Disk and device usage, activity, latency and saturation.

----

:graph_category: **environment**
:Description: Graphs the environment around the server.
:Examples: External temperature, light or other radiation, humidity,
           noise and vibration.

----

Role specific categories
------------------------

:graph_category: **www**
:Description: Used for graphing web server performance and use.
:Examples: Requests, bytes, errors, cache hit rate for Apache httpd,
           nginx, lighttpd, varnish, hitch, and other web servers,
           caches or TLS wrappers.

----

:graph_category: **database**
:Description: Used for graphing database system use and performance.
:Examples: MySQL, PosgreSQL, MongoDB, Memcached, Redis.
:Comment: Some database systems may have enough munin plugins to
          warrant a graph_category on their own.

----

:graph_category: **mail**
:Description: Used for graphing mail servers and traffic.
:Examples: Postfix, Exim, Sendmail, antispam and antimalware
           components for these.
:Comment: For monitoring a large mail system, it makes sense to
          override this with configuration on the munin master, and
          make graph categories for the mail roles you provide. Mail
          Transfer Agent (postfix and exim), Mail Delivery Agent
          (filtering, sorting and storage), Mail Retrieval Agent (imap
          server).

----

:graph_category: **security**
:Description: Graphs security information.
:Examples: Login failures, available security upgrades, number of CVEs
           in the running kernel fixed by the lastest installed
           kernel, firewall counters.

----

Application specific categories
-------------------------------

:graph_category: **tomcat**
:Description: For whatever is going on within your tomcat instances
:Comment: Graphing resource usage, computing time, threads, IO. Access
          counters for applications running within Tomcat.
