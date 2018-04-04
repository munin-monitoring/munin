.. _custom-rrd-sizing:

============================
Per plugin custom rrd sizing
============================

.. index::
   triple: rrd; graph_data_size; master configuration;

Choosing the RRD sizing is possible via the config option :ref:`graph_data_size <graph_data_size>` since 1.4.0, but for 2.0 there is also a custom format.

.. note:: The **configuration should be done on the Munin Master** (:ref:`munin.conf <munin.conf>`) as the plugins usually do not integrate this config option in their setup!

Objective
=========

The object of this extension is to help with two issues:

* Per default there are only two values ``normal`` and ``huge``. For some users this isn't enough, specially coupled with the :ref:`update_rate <update_rate>` option. A new special value ``custom``, followed by its definition should offer as much flexibility as anyone needs.
* The RRD sizing is global. Since :ref:`update_rate <update_rate>` is per plugin, this should also be per plugin.

The custom format
=================

There are 2 custom formats: the *computer* one, and the *human-readable* one. The *human-readable* one will be converted on-the-fly to the *computer* one.

computer-readable
-----------------

The format is comma-separated:

::

  full_rra_nb, multiple_1 multiple_rra_nb_1, multiple_2 multiple_rra_nb_2, ... multiple_N multiple_rra_nb_N

* ``multiple_N`` is the step of the RRA, in multiple of the :ref:`update_rate <update_rate>` of the plugin.
* ``multiple_rra_nb_N`` is the number of RRA frames to keep. The total time amount is function of ``multiple_N``.

In this format the original values ``normal``/``huge`` can be translated:

* ``normal`` meaning ``custom 576, 6 432, 24 540, 288 450``
* ``huge`` meaning ``custom 115200``

.. note:: The first multiple isn't asked, since it's always 1 (full resolution).

human-readable
--------------

Editing the computer format is powerful, but not very friendly. So, another format is available that specifies time duration instead of multiples. It is therefore independent of the :ref:`update_rate <update_rate>` of the plugin.

The format is still comma-separated, only the elements are translated:

::

  time_res_1 for time_duration_1, time_res_2 for time_duration_2, ... time_res_N for time_duration_N

* ``time_res_N`` represents the step of the RRA.
* ``time_duration_N`` represents the time of RRA frames to keep. The actual number of frames is function of ``time_res_N``.

The format for both fields is the same : a number followed by a unit like **134d** or **67w**.

The units are case sensitive and mean:

* ``s``: second
* ``m``: minute (60s)
* ``h``: hour (60m)
* ``d``: day (24h)
* ``w``: week (7d)
* ``t``: month (31d)
* ``y``: year (365d)

In this format the original values ``normal``/``huge`` can be translated:

* ``normal`` meaning ``custom 2d, 30m for 9d, 2h for 45d, 1d for 450d``
* ``huge`` meaning ``custom 400d``

.. note:: The 2 last units (``t`` and ``y``) are a fixed number of days. They do **not** take the real number of days in the current month.

Notes
=====

* The RRA is always created with a 10% increase so you can really compare on 10% of the period instead of just the last value.

Issues
======

* If a human readable config value isn't a multiple of :ref:`update_rate <update_rate>`, no graph should be emitted, so the user is immediatly alerted of his misconfiguration.
* The first number always represent the full resolution: :ref:`update_rate <update_rate>`.
