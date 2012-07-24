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
     graphs in PNG format from the RRD files. See also
     :ref:`munin-cgi-graph`.

   * :ref:`munin-limits` is run by :ref:`munin-cron`. It notifies any
     configured contacts if a value moves between "ok", "warn" or
     "crit". Munin is commonly used in combination with Nagios, which
     is then configured as a contact.

   * :ref:`munin-html` is run by :ref:`munin-cron`. It generates HTML
     pages. See also :ref:`munin-cgi-html`.

   * :ref:`munin-cgi-graph` is run by a web server. If graph_strategy
     is set to "cgi", munin-cron will not run munin-graph, and assumes
     that the web server runs :ref:`munin-cgi-graph` instead.

   * :ref:`munin-cgi-html` is run by a web server. If html_strategy is
     set to "cgi", munin-cron will not run munin-html, and assumes
     that the web server runs :ref:`munin-cgi-html` instead.

Configuration
=============

The munin master has its primary configuration file at
:ref:`/etc/munin/munin.conf <munin.conf>`.

Other documentation
===================

.. toctree::
   :maxdepth: 2

   rrdcached.rst
