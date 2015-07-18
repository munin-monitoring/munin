.. _plugin-reference:

==================
 Plugin reference
==================

.. index::
   pair: plugin; fields

.. _plugin_attributes_global:

On a configuration run, the plugin is called with the argument "config". The
following attributes are used.

Global attributes
=================

.. _graph_args:

:Attribute: **graph_args**
:Value: string
:Type: optional
:Description: Arguments for the rrd grapher. This is used to control how the generated graph looks, and how values are interpreted or presented.
:See also: rrdgraph_
:Default:

============

.. _graph_category:

:Attribute: **graph_category**
:Value: lower case string, no whitespace
:Type: optional
:Description: Category used to sort the graph on the generated index web page.
:See also: `Well known categories <http://munin-monitoring.org/wiki/graph_category_list>`_
:Default: 'other'

============

.. _graph_height:

:Attribute: **graph_height**
:Value: integer (pixel)
:Type: optional
:Description: The height of the graph. Note that this is only the graph's height and not the height of the whole PNG image.
:See also:
:Default: 200

============

.. _graph_info:

:Attribute: **graph_info**
:Value: html text
:Type: optional
:Description: Provides general information on what the graph shows.
:See also:
:Default:

============

.. _graph_order:

:Attribute: **graph_order**
:Value: space separated list of data sources (fieldnames)
:Type: optional
:Description:
  | Ensures that the listed fields are displayed in specified order. Any additional fields are added in the order of appearance after fields appearing on this list.
  |
  | This attribute is also used for "loaning", which is the practice of taking data sources from other graphs.
:See also: `Loaning Data <http://munin-monitoring.org/wiki/LoaningData>`_
:Default:

============

.. _graph_period:

:Attribute: **graph_period**
:Value: second|minute|hour
:Type: optional
:Description:
  | Controls the time unit munin (actually rrd) uses to calculate the average rates of change. Changing the default "second" to "minute" or "hour" is useful in cases of a low frequency of whatever the plugin is measuring.
  |
  | Changing the graph_period makes sense only when the data type is COUNTER or DERIVE.
  |
  | This does not change the sample interval - this remains per default at 5 minutes.
:See also:
:Default: second

============

.. _graph_scale:

:Attribute: **graph_scale**
:Value: yes|no
:Type: optional
:Description: Per default the unit written on the graph will be scaled. So instead of 1000 you will see 1k or 1M for 1000000. You may disable autoscale by setting this to 'no'.
:See also:
:Default: 'yes'

============

.. _graph_title:

:Attribute: **graph_title**
:Value: string
:Type: required
:Description: Sets the title of the graph
:See also:
:Default:

============

.. _graph_total:

:Attribute: **graph_total**
:Value: string
:Type: optional
:Description:
  | If set, summarizes all the data sources' values and reports the results in an extra row in the legend beneath the graph. The value you set here is used as label for that line.
  | 
  | Note that, since Munin version 2.1, using the special ``undef`` keyword disables it (to override in munin.conf).
:See also:
:Default:

============

.. _graph_vlabel:

:Attribute: **graph_vlabel**
:Value: string
:Type: optional
:Description: Label for the vertical axis of the graph. Don't forget to also mention the unit ;)
:See also:
:Default:

============

.. _graph_width:

:Attribute: **graph_width**
:Value: integer (pixel)
:Type: optional
:Description: The width of the graph. Note that this is only the graph's width and not the height of the whole PNG image.
:See also: 
:Default: 400

============

.. _host_name:

:Attribute: **graph_width**
:Value: string
:Type: optional
:Description: Override the host name for which the plugin is run.
:See also:
:Default: Host name as declared in munin.conf.

============

.. _update:

:Attribute: **update**
:Value: yes | no
:Type: optional
:Description: 
  | Decides whether munin-update should fetch data for the graph.
  |
  | Note that the graph will be shown even if updates are disabled and then be blank.
:See also:
:Default: 'yes'

.. _update_rate:

============

:Attribute: **update_rate**
:Value: integer (seconds)
:Type: optional
:Description:
  | Sets the update_rate used by the munin master when it creates the RRD file.
  |
  | The update rate is the interval at which the RRD file expects to have data.
  |
  | This field requires a munin master version of at least 2.0.0
:See also:
:Default:

.. _plugin_attributes_data:

Data source attributes
======================

.. _datapoint.label:

:Attribute: **datapoint.label**
:Value: lower case string, no whitespace
:Type: required
:Description: The label used in the graph for this field
:See also:
:Default:

============

.. _datapoint.info:

:Attribute: **datapoint.info**
:Value: html text
:Type: optional
:Description: Additional html text for the generated graph web page, used in the field description table
:See also:
:Default:

============

.. _datapoint.warning:

:Attribute: **datapoint.warning**
:Value: integer, or integer:integer (signed)
:Type: optional
:Description: This field defines a threshold value or range. If the field value above the defined warning value, or outside the range, the service is considered to be in a "warning" state.
:See also:
:Default:

============

.. _datapoint.critical:

:Attribute: **datapoint.critical**
:Value: integer, or integer:integer (signed)
:Type: optional
:Description:  This field defines a threshold value or range. If the field value is above the defined critical value, or outside the range, the service is considered to be in  a "critical" state.
:See also:
:Default:

============

.. _datapoint.graph:

:Attribute: **datapoint.graph**
:Value: yes|no
:Type: optional
:Description: Determines if this datapoint should be visible in the generated graph.
:See also:
:Default: 'yes'

============

.. _datapoint.cdef:

:Attribute: **datapoint.cdef**
:Value: CDEF statement
:Type: optional
:Description:
  | A CDEF statement is a Reverse Polish Notation statement used to construct adatapoint from other datapoints.
  |
  | This is commonly used to calculate percentages.
:See also: cdeftutorial_
:Default:

============

.. _datapoint.draw:

:Attribute: **datapoint.draw**
:Value: AREA, LINE, LINE[n], STACK, AREASTACK, LINESTACK, LINE[n]STACK
:Type: optional
:Description:
  | Determines how the graph datapoints are displayed in the graph. The "LINE" takes an optional width suffix, commonly "LINE1", "LINE2", etc…
  |
  | The \*STACK values are specific to munin and makes the first a LINE, LINE[n] or AREA datasource, and the rest as STACK.
:See also: rrdgraph_
:Default: 'LINE'

============

.. _datapoint.type:

:Attribute: **datapoint.type**
:Value: GAUGE, COUNTER, DERIVE, ABSOLUTE
:Type: optional
:Description: Sets the RRD Data Source Type for this datapoint.  The type used may introduce restrictions for the value that can be used.
:See also: rrdcreate_
:Default: GAUGE

.. Note::
   COUNTER is now considered **harmful**. The same effect can be achieved with a DERIVE type, coupled with a ``min 0``.

============

On a data fetch run, the plugin is called with no arguments. the following
fields are used.

============

.. _datapoint.value:

:Attribute: **datapoint.value**
:Value: integer, decimal numbers, or "U" (may be signed). For DERIVE and COUNTER values this must be an integer. See rrdcreate_ for restrictions.
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
