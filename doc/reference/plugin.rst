.. _plugin-reference:

==================
 Plugin reference
==================

.. index::
   pair: plugin; fields

Fields
======

On a configuration run, the plugin is called with the argument "config". The
following fields are used.

+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| Field              | Value            | type     | Description                              | See also         | Default |
+====================+==================+==========+==========================================+==================+=========+
| graph_title        | string           | required | Sets the title of the graph              |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_args         | string           | optional | Arguments for the rrd grapher. This is   | rrdgraph_        |         |
|                    |                  |          | used to control how the generated graph  |                  |         |
|                    |                  |          | looks, and how values are interpreted or |                  |         |
|                    |                  |          | presented.                               |                  |         |
|                    |                  |          |                                          |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_vlabel       | string           | optional | Label for the vertical axis of the graph |                  |         |
|                    |                  |          |                                          |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_category     | lower case       | optional | Category used to sort the graph on the   |                  | misc    |
|                    | string, no       |          | generated index web page.                |                  |         |
|                    | whitespace       |          |                                          |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_info         | html text        | optional | Additional text for the generated graph  |                  |         |
|                    |                  |          | web page                                 |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_scale        | yes|no           | optional | If "yes", the generated graph will be    |                  | no      |
|                    |                  |          | scaled to the upper and lower values of  |                  |         |
|                    |                  |          | the datapoints within the graph.         |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| graph_order        | space separated  | optional | Ensures that the listed datapoints are   |                  |         |
|                    | list of          |          | displayed in order. Any additional       |                  |         |
|                    | graph.datapoints |          | datapoints are added in the order of     |                  |         |
|                    |                  |          | appearance after datapoitns appearing on |                  |         |
|                    |                  |          | this list.                               |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          | This field is also used for "borrowing", |                  |         |
|                    |                  |          | which is the practice of taking          |                  |         |
|                    |                  |          | datapoints from other graphs.            |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| update_rate        | integer          | optional | Sets the update_rate used by the munin   |                  |         |
|                    | (seconds)        |          | master when it creates the RRD file.     |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          | The update rate is the interval at which |                  |         |
|                    |                  |          | the RRD file expects to have data.       |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          | This field requires a munin master       |                  |         |
|                    |                  |          | version of at least 2.0.0                |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.label    | lower case       | required | The label used in the graph for this     |                  |         |
|                    | string, no       |          | field                                    |                  |         |
|                    | whitespace       |          |                                          |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.info     | html text        | optional | Additional html text for the generated   |                  |         |
|                    |                  |          | graph web page, used in the field        |                  |         |
|                    |                  |          | description table                        |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.warning  | integer, or      | optional | This field defines a threshold value or  |                  |         |
|                    | integer:integer  |          | range. If the field value above the      |                  |         |
|                    | (signed)         |          | defined warning value, or outside the    |                  |         |
|                    |                  |          | range, the service is considered to be in|                  |         |
|                    |                  |          | a "warning" state.                       |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.critical | integer, or      | optional | This field defines a threshold value or  |                  |         |
|                    | integer:integer  |          | range. If the field value is above the   |                  |         |
|                    | (signed)         |          | defined critical value, or outside the   |                  |         |
|                    |                  |          | range, the service is considered to be in|                  |         |
|                    |                  |          | a "critical" state.                      |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.graph    | yes|no           | optional | Determines if this datapoint should be   |                  | yes     |
|                    |                  |          | visible in the generated graph.          |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          |                                          |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.cdef     | CDEF statement   | optional | A CDEF statement is a Reverse Polish     | cdeftutorial_    |         |
|                    |                  |          | Notation statement used to construct a   |                  |         |
|                    |                  |          | datapoint from other datapoints.         |                  |         |
|                    |                  |          |                                          |                  |         |
|                    |                  |          | This is commonly used to calculate       |                  |         |
|                    |                  |          | percentages.                             |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+
| datapoint.draw     | AREA, LINE,      |          | Determines how the graph datapoints are  | rrdgraph_        | LINE    |
|                    | LINE[n], STACK,  |          | displayed in the graph. The "LINE" takes |                  |         |
|                    | AREASTACK,       |          | an optional width suffix, commonly       |                  |         |
|                    | LINESTACK,       |          | "LINE1", "LINE2", etc…                   |                  |         |
|                    | LINE[n]STACK     |          | The \*STACK values are specific to munin |                  |         |
|                    |                  |          | and makes the first a LINE, LINE[n] or   |                  |         |
|                    |                  |          | AREA datasource, and the rest as STACK.  |                  |         |
+--------------------+------------------+----------+------------------------------------------+------------------+---------+

On a data fetch run, the plugin is called with no arguments. the following
fields are used.

+-----------------+-----------------------+----------+------------------+------+------------+
| Field           | Value                 | type     | Description      | See  | Default    |
|                 |                       |          |                  | also |            |
+=================+=======================+==========+==================+======+============+
| datapoint.value | integer, scientific   | required | The value to be  |      | No default |
|                 | notation, or "U" (may |          | graphed.         |      |            |
|                 | be signed)            |          |                  |      |            |
|                 |                       |          |                  |      |            |
+-----------------+-----------------------+----------+------------------+------+------------+

.. index::
   pair: plugin; executing

Example
=======

This is an example of the plugin fields used with the "df" plugin. The
"munin-run" command is used to run the plugin from the command line.

Configuration run
-----------------

::

 # munin-run df config
 graph_title Filesystem usage (in %)
 graph_args --upper-limit 100 -l 0
 graph_vlabel %
 graph_category disk
 graph_info This graph shows disk usage on the machine.
 _dev_hda1.label /
 _dev_hda1.info / (ext3) -> /dev/hda1
 _dev_hda1.warning 92
 _dev_hda1.critical 98

Data fetch run
--------------

::

 # munin-run df
 _dev_hda1.value 83


.. _cdeftutorial: http://oss.oetiker.ch/rrdtool/tut/cdeftutorial.en.html

.. _rrdgraph: http://oss.oetiker.ch/rrdtool/doc/rrdgraph_graph.en.html
