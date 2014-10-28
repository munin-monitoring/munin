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

.. _graph_title:

============

:Field: **graph_title**
:Value: string
:Type: required
:Description: Sets the title of the graph
:See also:
:Default:

.. _graph_args:

============

:Field: **graph_args**
:Value: string
:Type: optional
:Description: Arguments for the rrd grapher. This is used to control how the generated graph looks, and how values are interpreted or presented.
:See also: rrdgraph_
:Default:

============

.. _graph_vlabel:

:Field: **graph_vlabel**
:Value: string
:Type: optional
:Description: Label for the vertical axis of the graph
:See also:
:Default:

============

.. _graph_category:

:Field: **graph_category**
:Value: lower case string, no whitespace
:Type: optional
:Description: Category used to sort the graph on the generated index web page.
:See also: `Well known categories <http://munin-monitoring.org/wiki/graph_category_list>`_
:Default: 'other'

============

.. _graph_info:

:Field: **graph_info**
:Value: html text
:Type: optional
:Description: Additional text for the generated graph web page
:See also:
:Default:

============

.. _graph_scale:

:Field: **graph_scale**
:Value: yes|no
:Type: optional
:Description: If "yes", the generated graph will be scaled to the uppper and lower values of the datapoints within the graph.
:See also:
:Default: 'no'

============

.. _graph_order:

:Field: **graph_order**
:Value: space separated list of graph.datapoints
:Type: optional
:Description: Ensures that the listed datapoints are displayed in order. Any additional datapoints are added in the order of appearance after datapoints appearing on this list.
   
  This field is also used for "borrowing", which is the practice of taking datapoints from other graphs.
:See also:
:Default:

============

.. _graph_period:

:Field: **graph_period**
:Value: second|minute|hour
:Type: optional
:Description: Control the unit of the data that will be displayed in the graphs. The default is "second".  Changing it to "minute" or "hour" is useful in cases of a low frequency of whatever the plugin is measuring.
  
  Changing the graph_period makes sense only when the data type is COUNTER or DERIVE.
  
  This does not change the sampling frequency of the data
:See also:
:Default:

============

.. _update_rate:

:Field: **update_rate**
:Value: integer (seconds)
:Type: optional
:Description: Sets the update_rate used by the munin master when it creates the RRD file.
  
  The update rate is the interval at which the RRD file expects to have data.
  
  This field requires a munin master version of at least 2.0.0
:See also:
:Default:

============

.. _datapoint.label:

:Field: **datapoint.label**
:Value: lower case string, no whitespace
:Type: required
:Description: The label used in the graph for this field
:See also:
:Default:

============

.. _datapoint.info:

:Field: **datapoint.info**
:Value: html text
:Type: optional
:Description: Additional html text for the generated graph web page, used in the field description table
:See also:
:Default:

============

.. _datapoint.warning:

:Field: **datapoint.warning**
:Value: integer, or integer:integer (signed)
:Type: optional
:Description: This field defines a threshold value or range. If the field value above the defined warning value, or outside the range, the service is considered to be in a "warning" state.
:See also:
:Default:

============

.. _datapoint.critical:

:Field: **datapoint.critical**
:Value: integer, or integer:integer (signed)
:Type: optional
:Description:  This field defines a threshold value or range. If the field value is above the defined critical value, or outside the range, the service is considered to be in  a "critical" state.
:See also:
:Default:

============

.. _datapoint.graph:

:Field: **datapoint.graph**
:Value: yes|no
:Type: optional
:Description: Determines if this datapoint should be visible in the generated graph.
:See also:
:Default: 'yes'

============

.. _datapoint.cdef:

:Field: **datapoint.cdef**
:Value: CDEF statement
:Type: optional
:Description: A CDEF statement is a Reverse Polish Notation statement used to construct adatapoint from other datapoints.
  
  This is commonly used to calculate percentages.
:See also: cdeftutorial_
:Default:

============

.. _datapoint.draw:

:Field: **datapoint.draw**
:Value: AREA, LINE, LINE[n], STACK, AREASTACK, LINESTACK, LINE[n]STACK
:Type: optional
:Description: Determines how the graph datapoints are displayed in the graph. The "LINE" takes an optional width suffix, commonly "LINE1", "LINE2", etc…
  
  The \*STACK values are specific to munin and makes the first a LINE, LINE[n] or AREA datasource, and the rest as STACK.
:See also: rrdgraph_
:Default: 'LINE'

============

.. _datapoint.type:

:Field: **datapoint.type**
:Value: GAUGE, COUNTER, DERIVE, ABSOLUTE
:Type: optional
:Description: Sets the RRD Data Source Type for this datapoint.  The type used may introduce restrictions for the value that can be used.
:See also: rrdcreate_
:Default:

============

On a data fetch run, the plugin is called with no arguments. the following
fields are used.

============

.. _datapoint.value:

:Field: **datapoint.value**
:Value: integer, decimal numbers, or "U" (may be signed). See rrdcreate_ for restrictions.
:Type: required
:Description: The value to be graphed.
:See also:
:Default: No default

============

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

.. _rrdcreate: http://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html
