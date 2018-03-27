.. _plugin-reference:

==================
 Plugin reference
==================

.. index::
   pair: plugin; fields

.. _plugin_attributes_global:

When a plugin is invoked with "config" as (the only) argument it is expected
to output configuration information for the graph it supports.
This output consists of a number of attributes.
They are divided into one set of global attributes and
then one or more set(s) of datasource-specific attributes.
(Things are more complex in the case of :ref:`Multigraph plugins <plugin-multigraphing>` due to their nested hierarchy.)

Global attributes
=================

.. _graph:

:Attribute: **graph**
:Value: yes|no
:Type: optional
:Description: Decides whether to draw the graph.
:See also:
:Default: yes

============

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
:Value: string (Allowed characters: [a-z0-9-.])
:Type: optional
:Description: 
  | Name of the category used to sort the graphs on the generated index web page.
  | Lower case string as we like a consistent view and want to avoid duplicates.
  | No whitespace as this makes the build of Munin Gallery a lot easier.
:See also: :ref:`Well known categories <plugin-graph-category>`, `Plugin Gallery <http://munin-monitoring.org/wiki/PluginGallery>`_
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
  | Ensures that the listed fields are displayed in specified order. Any additional fields are added in the order of appearance after fields appearing on this list. This attribute is useful when STACKing data sources with :ref:`fieldname.draw <fieldname.draw>`.
  |
  | It's also used for :ref:`loaning data <example-plugin-aggregate>` from other data sources (other plugins), which enables Munin to :ref:`create aggregate or other kinds of combined graphs <aggregate-graphs>`.
:See also: `Loaning Data <http://munin-monitoring.org/wiki/LoaningData>`_, :ref:`Aggregate Graphs <aggregate-graphs>`
:Default: None (If not set, the order of the graphs follows the order in which the data sources are read; i.e. the order that the plugin itself provides.)

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
  | This does not change the sample interval - it remains per default at 5 minutes.
:See also:
:Default: second

============

.. _graph_printf:

:Attribute: **graph_printf**
:Value: Default format string for data source values.
:Type: optional
:Description:
   | Controls the format munin (actually rrd) uses to display data
   | source values in the graph legend.
:See also:
:Default: "%7.2lf" if --base is 1024, otherwise "%6.2lf"

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
:Value: string [a-zA-Z0-9-.]
:Type: required
:Description: Sets the title of the graph
:See also:
:Default: The plugin's file name

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
:Description: The width of the graph. Note that this is only the graph's width and not the width of the whole PNG image.
:See also:
:Default: 400

============

.. _host_name:

:Attribute: **host_name**
:Value: string [a-zA-Z0-9-.]
:Type: optional
:Description: Fully qualified host name (FQDN). Override the host name for which the plugin is run. Should normally **not** be set in the plugin. It is meant to be used when the munin-node acts as proxy to monitor remote hosts e.g. per SNMP plugins. In these cases you have to add an own entry for the remote host in the Munin master configuration to pick up these additional host names.
:See also: :ref:`Using SNMP plugins <tutorial-snmp>`
:Default: Host name as declared in munin.conf.

============

.. _multigraph:

:Attribute: **multigraph**
:Value: string
:Type: optional
:Description:
  | Herewith the plugin tells that it delivers a hierarchy of graphs. The attribute will show up multiple times in the config section, once for each graph that it contains. It announces the name of the graph for which the further configuration attributes then follow.
  |
  | This feature is available since Munin version 1.4.0.
:See also: :ref:`Multigraph plugins <plugin-multigraphing>`
:Default:

============

.. _update:

:Attribute: **update**
:Value: yes | no
:Type: optional
:Description:
  | Decides whether munin-update should fetch data for the graph.
  |
  | Note that the graph will be shown even if updates are disabled and then be blank.
:See also: Set to ``no`` when dealing with :ref:`Graph aggregation <example-plugin-aggregate>` and/or :ref:`loaning data <example-aggregated-stack>`.
:Default: 'yes'

.. _update_rate:

============

:Attribute: **update_rate**
:Value: integer (seconds)
:Type: optional
:Description:
  | Sets the update_rate used by the Munin master when it creates the RRD file.
  |
  | The update rate is the interval at which the RRD file expects to have data.
  |
  | This attribute requires a Munin master version of at least 2.0.0
:See also:
:Default:

.. _plugin_attributes_data:

Data source attributes
======================

.. _notes-on-fieldnames:

Notes on field names
--------------------

Each data source in a plugin must be identified by a field name.

The characters must be ``[a-zA-Z0-9_]``, while the first character must be ``[a-zA-Z_]``.

Reserved keyword(s): A field must not be named ``root``. If it's done `Graph generation would be stopped <http://munin-monitoring.org/ticket/921>`_.

In earlier versions of Munin the fieldname may not exceed 19 characters in length.  Since munin 1.2 this limit has been circumvented.

Field name attributes
---------------------

.. _fieldname.cdef:

:Attribute: **{fieldname}.cdef**
:Value: CDEF statement
:Type: optional
:Description:
  | A CDEF statement is a Reverse Polish Notation statement. It can be used here to modify the value(s) before graphing.
  |
  | This is commonly used to calculate percentages. See the FAQ_ for examples.
:See also: cdeftutorial_
:Default:

============

.. _fieldname.colour:

:Attribute: **{fieldname}.colour**
:Value: Hexadecimal colour code
:Type: optional
:Description: Custom specification of colour for drawing curve. Available since 1.2.5 and 1.3.3.
:See also:
:Default: Selected by order sequence from Munin standard colour set

============

.. _fieldname.critical:

:Attribute: **{fieldname}.critical**
:Value: integer or decimal numbers (both may be signed)
:Type: optional
:Description: Can be a max value or a range separated by colon. E.g. "min:", ":max", "min:max", "max". Used by munin-limits to submit an error code indicating critical state if the value fetched is outside the given range.
:See also: :ref:`Let Munin croak alarm <tutorial-alert>`
:Default:

============

.. _fieldname.draw:

:Attribute: **{fieldname}.draw**
:Value: AREA, LINE, LINE[n], STACK, AREASTACK, LINESTACK, LINE[n]STACK
:Type: optional
:Description:
  | Determines how the data points are displayed in the graph. The "LINE" takes an optional width suffix, commonly "LINE1", "LINE2", etc…
  |
  | The \*STACK values are specific to munin and makes the first a LINE, LINE[n] or AREA datasource, and the rest as STACK.
:See also: rrdgraph_
:Default: 'LINE1' since Munin version 2.0.

============

.. _fieldname.extinfo:

:Attribute: **{fieldname}.extinfo**
:Value: html text
:Type: optional
:Description: Extended information that is included in alert messages (see :ref:`warning <fieldname.warning>` and :ref:`critical <fieldname.critical>`). Since 1.4.0 it is also included in the HTML pages.
:See also:
:Default:

============

.. _fieldname.graph:

:Attribute: **{fieldname}.graph**
:Value: yes|no
:Type: optional
:Description: Determines if the data source should be visible in the generated graph.
:See also:
:Default: yes

============

.. _fieldname.info:

:Attribute: **{fieldname}.info**
:Value: html text
:Type: optional
:Description: Explanation on the data source in this field. The Info is displayed in the field description table on the detail web page of the graph.
:See also:
:Default:

============

.. _fieldname.label:

:Attribute: **{fieldname}.label**
:Value: anything except # and \\
:Type: required
:Description: The label used in the legend for the graph on the HTML page.
:See also:
:Default:

============

.. _fieldname.line:

:Attribute: **{fieldname}.line**
:Value: value [:color[:label]]
:Type: optional
:Description: Adds a horizontal line with the fieldname's colour (HRULE) at the value defined. Will not show if outside the graph's scale.
:See also: rrdgraph_
:Default:

.. Note::
     Didn't work here (munin-2.0.25-2.el6.noarch, rrdtool-1.3.8-7.el6.x86_64). Please investigate on your platforms and report the versions of Munin and rrdtool to Munin mailinglist if it worked for you.

============

.. _fieldname.max:

:Attribute: **{fieldname}.max**
:Value: numerical of same data type as the field it belongs to.
:Type: optional
:Description: Sets a maximum value. If the fetched value is above "max", it will be discarded.
:See also:
:Default:

============

.. _fieldname.min:

:Attribute: **{fieldname}.min**
:Value: numerical of same data type as the field it belongs to.
:Type: optional
:Description: Sets a minimum value. If the fetched value is below "min", it will be discarded.
:See also:
:Default:

============

.. _fieldname.negative:

:Attribute: **{fieldname}.negative**
:Value: {fieldname} of related field.
:Type: optional
:Description: You need this for a "mirrored" graph. Values of the named field will be drawn below the X-axis then (e.g. plugin ``if_`` that shows traffic going in and out as mirrored graph).
:See also: See the :ref:`Best Current Practices for good plugin graphs <plugin-bcp-direction>` for examples
:Default:

============

.. _fieldname.stack:

:Attribute: **{fieldname}.stack**
:Value: List of field declarations referencing the data sources from other plugins by their virtual path. (FIXME: Explanation on topic "virtual path" should be added elsewhere to set a link to it here)
:Type: optional
:Description: Function for creating stacked graphs.
:See also: `How do I use fieldname.stack? <http://munin-monitoring.org/wiki/faq#Q:HowdoIusefieldname.stack>`_ and :ref:`Graph aggregation stacking example <example-aggregated-stack>`
:Default:

============

.. _fieldname.sum:

:Attribute: **{fieldname}.sum**
:Value: List of fields to summarize. If the fields are loaned from other plugins they have to be referenced by their virtual path. (FIXME: Explanation on topic "virtual path" should be added elsewhere to set a link to it here)
:Type: optional
:Description: Function for creating summary graphs.
:See also: `How do I use fieldname.sum? <http://munin-monitoring.org/wiki/faq#Q:HowdoIusefieldname.sum>`_ and :ref:`Graph aggregation by example <example-plugin-aggregate>`
:Default:

============

.. _fieldname.type:

:Attribute: **{fieldname}.type**
:Value: GAUGE|COUNTER|DERIVE|ABSOLUTE
:Type: optional
:Description: Sets the RRD Data Source Type for this field. The values **must** be written in capitals. The type used may introduce restrictions for ``{fieldname.value}``.
:See also: :ref:`Datatypes <datatypes>`, rrdcreate_
:Default: GAUGE

.. Note::
   COUNTER is now considered **harmful** because you can't specify the wraparound value. The same effect can be achieved with a DERIVE type, coupled with a ``min 0``.

============

.. _fieldname.warning:

:Attribute: **{fieldname}.warning**
:Value: integer or decimal numbers (both may be signed)
:Type: optional
:Description: Can be a max value or a range separated by colon. E.g. "min:", ":max", "min:max", "max". Used by munin-limits to submit an error code indicating warning state if the value fetched is outside the given range.
:See also: :ref:`Let Munin croak alarm <tutorial-alert>`
:Default:

============

On a data fetch run, the plugin is called with no arguments. the following
fields are used.

============

.. _fieldname.value:

:Attribute: **{fieldname}.value**
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


.. _cdeftutorial: https://oss.oetiker.ch/rrdtool/tut/cdeftutorial.en.html

.. _rrdgraph: https://oss.oetiker.ch/rrdtool/doc/rrdgraph_graph.en.html

.. _rrdcreate: https://oss.oetiker.ch/rrdtool/doc/rrdcreate.en.html

.. _FAQ: http://munin-monitoring.org/wiki/faq
