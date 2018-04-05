.. _master-index:

==================
 The Munin master
==================

For an overview see :ref:`Architectural Fundamentals <architecture-index>`


Role
====

The munin master is responsible for gathering data from munin nodes.
It stores this data in RRD [#]_, files, and graphs them on request.
It also checks whether the fetched values fell below or go over specific
thresholds (warning, critical) and will send alerts if this happens and
the administrator configured it to do so.

.. [#] `RRDtool <https://oss.oetiker.ch/rrdtool/>`_ (acronym for round-robin database tool) aims to handle time-series data like network bandwidth, temperatures, CPU load, etc. The data are stored in a round-robin database (circular buffer), thus the system storage footprint remains constant over time. Source Wikipedia: http://en.wikipedia.org/wiki/RRDtool

Components
==========

The following components are part of munin-master:

.. hlist::

   * :ref:`munin-cron` runs :ref:`munin-limits` and
     :ref:`munin-update`.

   * :ref:`munin-update` is run by :ref:`munin-cron`. It is the munin
     data collector, and it fetches data from :ref:`munin nodes
     <munin-node>`, which is then stored in RRD files.

   * :ref:`munin-limits` is run by :ref:`munin-cron`. It notifies any
     configured contacts if a value moves between "ok", "warn" or
     "crit". Munin is commonly used in combination with Nagios, which
     is then configured as a contact.

Configuration
=============

The munin master has its primary configuration file at
:ref:`/etc/munin/munin.conf <munin.conf>`.

Fetching values
===============

.. toctree::
   :maxdepth: 2

   network-protocol.rst

Graphing Charts
===============

Other documentation
===================

.. toctree::
   :maxdepth: 2

   ../tutorial/alert.rst
   rrdcached.rst
