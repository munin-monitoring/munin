.. _syntax:

=========================
Munin's Syntax
=========================

POD style documentation
=======================

**Wiki Pages:**

- `munindoc <http://munin-monitoring.org/wiki/munindoc>`_

Configuration
=============

- For the :ref:`Munin master <master-index>` in :ref:`/etc/munin/munin.conf <munin.conf>`.
- For the :ref:`Munin node <node-index>` daemon in :ref:`/etc/munin/munin-node.conf <munin-node.conf>`.
- For the :ref:`Munin plugins <plugin-index>` in :ref:`/etc/munin/plugin-conf.d/.. <plugin-conf.d>`.

.. index::
   pair: plugin; magic marker

.. _magic-markers:

Magic Markers
=============

Munin can only autoconfigure plugins that have the corresponding (optional) magic markers.
Magic markers are prefixed with ``#%#`` and consists of a keyword, an equal sign, and one or more whitespace-separated values.

For a plugin that is part of munin, you should expect to see:

.. code-block:: perl

 #%# family=auto
 #%# capabilities=autoconf suggest

.. index::
   pair: magic marker; family

family
^^^^^^

For the magic marker ``family``, the following values may be used.

.. index::
   triple: magic marker; family; auto

auto
    This is a plugin that can be automatically installed and configured by ``munin-node-configure``

.. index::
   triple: magic marker; family; snmpauto

snmpauto
    This is a plugin that can be automatically installed and configured by ``munin-node-configure`` if called with ``--snmp`` (and related arguments)

.. index::
   triple: magic marker; family; manual

manual
    This is a plugin that is to be manually configured and installed

.. index::
   triple: magic marker; family; contrib

contrib
    This is a plugin which has been contributed to the munin project by others, and has not been checked for conformity to the plugin standard.

.. index::
   triple: magic marker; family; test

test
    This is a test plugin. It is used when testing munin.

.. index::
   triple: magic marker; family; example

example
    This is an example plugin. It serves as a starting point for writing new plugins.

.. index::
   pair: magic marker; capabilities

capabilities
^^^^^^^^^^^^
For the magic marker ``capabilities``, the following values may be used.

.. index::
   triple: magic marker; capability; autoconf

autoconf
    The plugin may be automatically configured by "munin-node-configure".

.. index::
   triple: magic marker; capability; suggest

suggest
    The plugin is a wildcard plugin, and may suggest a list of link names for the plugin.

.. _datatypes:

Datatypes
=========

.. _datatype_gauge:

GAUGE
^^^^^

"is for things like temperatures or number of people in a room or the value of a RedHat share." (Source: `rrdcreate man page <https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html#IGAUGE>`_)

If a plugin author does not declare datatype explicitly, GAUGE is the default datatype.

.. _datatype_counter:

COUNTER
^^^^^^^

"is for continuous incrementing counters like the ifInOctets counter in a router. The COUNTER data source assumes that the counter never decreases, except when a counter overflows. The update function takes the overflow into account. The counter is stored as a per-second rate. When the counter overflows, RRDtool checks if the overflow happened at the 32bit or 64bit border and acts accordingly by adding an appropriate value to the result." (Source: `rrdcreate man page <https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html#ICOUNTER>`_)

.. Note::

  on COUNTER vs DERIVE

  by Don Baarda <don.baarda@baesystems.com> from `https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html <https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html#IDDERIVE>`_

  If you cannot tolerate ever mistaking the occasional counter reset for a legitimate counter wrap, and would prefer "Unknowns" for all legitimate counter wraps and resets, always use DERIVE with min=0. Otherwise, using COUNTER with a suitable max will return correct values for all legitimate counter wraps, mark some counter resets as "Unknown", but can mistake some counter resets for a legitimate counter wrap.

  For a 5 minute step and 32-bit counter, the probability of mistaking a counter reset for a legitimate wrap is arguably about 0.8% per 1Mbps of maximum bandwidth. Note that this equates to 80% for 100Mbps interfaces, so for high bandwidth interfaces and a 32bit counter, DERIVE with min=0 is probably preferable. If you are using a 64bit counter, just about any max setting will eliminate the possibility of mistaking a reset for a counter wrap.

.. _datatype_derive:

DERIVE
^^^^^^
"will store the derivative of the line going from the last to the current value of the data source. This can be useful for gauges, for example, to measure the rate of people entering or leaving a room. Internally, derive works exactly like COUNTER but without overflow checks. So if your counter does not reset at 32 or 64 bit you might want to use DERIVE and combine it with a MIN value of 0." (Source: `rrdcreate man page <https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html#IDERIVE>`_)

.. _datatype_absolute:

ABSOLUTE
^^^^^^^^

"is for counters which get reset upon reading. This is used for fast counters which tend to overflow. So instead of reading them normally you reset them after every read to make sure you have a maximum time available before the next overflow. Another usage is for things you count like number of messages since the last update."  (Source: `rrdcreate man page <https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html#IABSOLUTE>`_)

.. note:: When `loaning data <http://munin-monitoring.org/wiki/LoaningData>`_ from other graphs, the ``{fieldname}.type`` must be set to the same data type as the original data. If not, Munin default to searching for gauge files, i.e. files ending with ``-g.rdd``. See :ref:`dbdir <dbdir>` for the details on RRD filenames.
