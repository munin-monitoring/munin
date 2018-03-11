.. _example-graph-args:
.. index::
   single: graph_args
   pair: example; graph_args

=======================
 Recommended graph_args
=======================


Set arguments for the rrd grapher with attribute :ref:`graph_args <graph_args>`.
This is used to control how the generated graph looks, and how values are interpreted or presented.

You can override plugin defaults on Munin master via your own settings on plugin level in :ref:`munin.conf`.

See `rrdgraph man page <https://oss.oetiker.ch/rrdtool/doc/rrdgraph.en.html>`_ for more details.

Scale
=====

.. option:: --logarithmic

   Plot these values on a logarithmic scale.
   Should almost never be used, but probably more often than we do now.
   Logarithmic scale is very useful when the collected values spans
   more than one to two magnitudes. It makes it possible to see
   the different small values as well as the different large values
   - instead of just the large values as usual.

   Logarithmic has been tested on netstat (connection count)
   and some other graphs with good results.

Units
=====

See :ref:`Best Current Practices for good plugin graphs <plugin-bcp-graphscaling>`

.. option:: --base <value>

   Set to **1024** for things that are counted in binary units, such as memory (but not network bandwidth)

   Set to **1000** for default SI units

.. option:: --units-exponent <value>

   Set to **3** force display unit to K, **-6** would force display in u/micro.

Axis
====

.. option:: --lower-limit <value>

   Start the Y-axis at ``value`` e.g. ``--lower-limit 0`` (also seen as: ``-l 0``)

.. option:: --upper-limit <value>

   Set value to **100** for percentage graphs, ends the Y-axis at 100 (also seen as: ``-u 100``)

.. option:: --rigid

  Force rrdgraph y-axis scale to the set upper and lower limit.
  Usually, the graph scale can `overrun`. (also seen as: ``-r``)
