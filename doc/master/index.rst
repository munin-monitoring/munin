.. _master-index:

==================
 The Munin master
==================

Role
====

The munin master is responsible for gathering data from munin nodes.
It stores this data in RRD, and graphs them on request.

Components
==========

The following components are part of munin-master:

.. hlist::

   * :ref:`munin-cron` runs :ref:`munin-graph`, :ref:`munin-html`,
     :ref:`munin-limits` and :ref:`munin-update`.

   * :ref:`munin-update` is run by :ref:`munin-cron`. It is the munin
     data collector, and it fetches data from :ref:`munin nodes
     <munin-node>`, which is then stored in RRD files.

   * :ref:`munin-graph` is run by :ref:`munin-cron`. It generates
     metadata used by :ref:`munin-cgi-graph`. If graph_strategy is set
     to "cron", it generates static graphs in PNG format.

   * :ref:`munin-limits` is run by :ref:`munin-cron`. It notifies any
     configured contacts if a value moves between "ok", "warn" or
     "crit". Munin is commonly used in combination with Nagios, which
     is then configured as a contact.

   * :ref:`munin-html` is run by :ref:`munin-cron`. It generates
     metadata used by :ref:`munin-cgi-html`. If html_strategy is set
     to "cron", it also generates static HTML pages.

   * :ref:`munin-cgi-graph` is run by a web server, and generates
     graphs on request.

   * :ref:`munin-cgi-html` is run by a web server, and generates HTML
     pages on request.

Configuration
=============

The munin master has its primary configuration file at
:ref:`/etc/munin/munin.conf <munin.conf>`.

Other documentation
===================

.. toctree::
   :maxdepth: 2

   rrdcached.rst
