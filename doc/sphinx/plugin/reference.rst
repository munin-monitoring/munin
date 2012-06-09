==================
 Plugin reference
==================

Fields
======

On a configuration run, the plugin is called with the argument "config". The
following fields are used.

+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| Field              | Value           | type     | Description                             | See         | Default |
+====================+=================+==========+=========================================+=============+=========+
| graph_title        | string          | required | Sets the title of the graph             |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| graph_args         | string          | optional | Arguments for the rrd grapher.          | rrdgraph(1) |         |
|                    |                 |          | This is used to control how             | man page    |         |
|                    |                 |          | the generated graph looks, and          |             |         |
|                    |                 |          | how values are interpreted or           |             |         |
|                    |                 |          | presented.                              |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| graph_vlabel       | string          | optional | Label for the vertical axis             |             |         |
|                    |                 |          | of the graph                            |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| graph_category     | lower case      | optional | Category used to sort the               |             | misc    |
|                    | string, no      |          | graph on the generated index            |             |         |
|                    | whitespace      |          | web page.                               |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| graph_info         | html text       | optional | Additional text for the                 |             |         |
|                    |                 |          | generated graph web page                |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| datapoint.label    | lower case      | required | The label used in the graph             |             |         |
|                    | string, no      |          | for this field                          |             |         |
|                    | whitespace      |          |                                         |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| datapoint.info     | html text       | optional | Additional html text for the            |             |         |
|                    |                 |          | generated graph web page, used          |             |         |
|                    |                 |          | in the field description table          |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| datapoint.warning  | integer, or     | optional | This field defines a threshold          |             |         |
|                    | integer:integer |          | value or range. If the field value      |             |         |
|                    | (signed)        |          | above the defined warning value,        |             |         |
|                    |                 |          | or outside the range, the service is    |             |         |
|                    |                 |          | considered to be in a "warning" state.  |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+
| datapoint.critical | integer, or     | optional | This field defines a threshold          |             |         |
|                    | integer:integer |          | value or range. If the field value      |             |         |
|                    | (signed)        |          | is above the defined critical value,    |             |         |
|                    |                 |          | or outside the range, the service is    |             |         |
|                    |                 |          | considered to be in a "critical" state. |             |         |
+--------------------+-----------------+----------+-----------------------------------------+-------------+---------+

On a data fetch run, the plugin is called with no arguments. the following
fields are used.

+-----------------+--------------+----------+------------------+-----+------------+
| Field           | Value        | type     | Description      | See | Default    |
+=================+==============+==========+==================+=====+============+
| datapoint.value | integer, or  | required | This is used per |     | No default |
|                 | "U"          |          |                  |     |            |
|                 | (integer may |          |                  |     |            |
|                 | be signed)   |          |                  |     |            |
+-----------------+--------------+----------+------------------+-----+------------+

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
