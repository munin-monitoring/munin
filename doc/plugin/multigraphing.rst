.. _plugin-multigraphing:

====================
 Multigraph plugins
====================

As of 1.4.0 Munin supports multigraph plugins. 

What are they?
==============

A multigraph plugin supports a "hierarchy of graphs" to provide drill-down from general graphs to more specific graphs. One of the most obvious cases for this is network switch graphing where showing per-port traffic for 48 ports in the main host view would be overwhelming. Therefore the snmp__if_multi plugin presents two graphs on the main host view: if_bytes and if_errors. If you click on the if_bytes graph you will arrive at another page showing the throughput on all interfaces. If you click on the if_errors graph you will arrive on a page showing errors on all interfaces. 

When to use them?
=================

Ordinarily one does not want to use multigraph plugins. This is because they quickly become much more like "ordinary software", e.g. that the number of lines of code passes around 50-100 lines, and that the data structures become more complex than a very simple hash or array. Most Munin plugins are simple and quick (and fun) to write, and that is by many considered one of the killer features of Munin. A multigraph plugin quickly becomes more unwieldy to write and takes away the quickness and fun from plugin writing. 

But, if in your plugins you notice 
-  duplication of code 
-  duplication of work 
-  you have more data than you know how to present in one or a few graphs 

and this bothers you or makes things unnecessarily slow you may want to write a multigraph plugin 

Features often needed
---------------------

It turns out that multigraph plugins are written to generate graphs for all network devices or all disk devices on a system. There is a definitive need to provide filtering (include) features, such as device name patterns for disk devices or media types for network boxes so that only e.g. ethernet and ppp devices are included in the graphs, and not the loopback and serial devices (unless the serial device is actually interesting since it's really a long haul WAN line). Or, on the other hand a exclude feature to drop specifically uninteresting things. 
How to make one?

It's quite simple, even if it's not as simple as without multigraph. 

The setup is done in the usual way, with graph_title and other configuration items for the two "root" graphs of the multigraph plugin: 
::

   multigraph if_bytes
   graph_title $host interface traffic
   graph_order recv send
   graph_args --base 1000
   graph_vlabel bits in (-) / out (+) per \${graph_period}
   graph_category network
   graph_info This graph shows the total traffic for $host
   
   send.info Bits sent/received by $host
   recv.label recv
   recv.type DERIVE
   recv.graph no
   recv.cdef recv,8,*
   recv.min 0
   send.label bps
   send.type DERIVE
   send.negative recv
   send.cdef send,8,*
   send.min 0
   
   multigraph if_errors
   graph_title $host interface errors
   graph_order recv send
   graph_args --base 1000
   graph_vlabel errors in (-) / out (+) per \${graph_period}
   graph_category network
   graph_info This graph shows the total errors for $host
   
   send.info Errors in outgoing/incoming traffic on $host
   recv.label recv
   recv.type DERIVE
   recv.graph no
   recv.cdef recv,8,*
   recv.min 0
   send.label bps
   send.type DERIVE
   send.negative recv
   send.cdef send,8,*
   send.min 0

Then for each of the interfaces the plugin emits these configuration items (interface number is indexed with $if in this, and should be replaced with name or number by the plugin itself, likewise for the other settings such as $alias, $speed and $warn. ${graph_period} is substituted by Munin. 

::
   multigraph if_bytes.if_$if

   graph_title Interface $alias traffic
   graph_order recv send
   graph_args --base 1000
   graph_vlabel bits in (-) / out (+) per \${graph_period}
   graph_category network
   graph_info This graph shows traffic for the "$alias" network interface.
   send.info Bits sent/received by this interface.
   recv.label recv
   recv.type DERIVE
   recv.graph no
   recv.cdef recv,8,*
   recv.max $speed
   recv.min 0
   recv.warning -$warn
   send.label bps
   send.type DERIVE
   send.negative recv
   send.cdef send,8,*
   send.max $speed
   send.min 0
   send.warning $warn
   
   multigraph if_errors.if_$if
   
   graph_title Interface $alias errors
   graph_order recv send
   graph_args --base 1000
   graph_vlabel bits in (-) / out (+) per \${graph_period}
   graph_category network
   graph_info This graph shows errors for the \"$alias\" network interface.
   send.info Errors in outgoing/incomming traffic on this interface.
   recv.label recv
   recv.type DERIVE
   recv.graph no
   recv.cdef recv,8,*
   recv.max $speed
   recv.min 0
   recv.warning 1
   send.label bps
   send.type DERIVE
   send.negative recv
   send.cdef send,8,*
   send.max $speed
   send.min 0
   send.warning 1

As you probably can see the hierarchy is provided by the "multigraph" keyword: 

::

   multigraph if_bytes
   multigraph if_bytes.if_1
   multigraph if_bytes.if_2
   ...
   multigraph if_errors
   multigraph if_errors.if_1
   multigraph if_errors.if_2
   ...

When it comes to getting readings from the plugin this is done with the normal fieldname.value protocol, but with the same multigraph "commands" between each value set as between the each "config" set. 

*Important:* The plugin's name is snmp__if_multi but, unlike all other plugins, that name never appears in the munin html pages. The "multigraph" keyword overrides the name of the plugin. If multiple plugins try to claim the same names (the same part of the namespace) this will be logged in munin-update.log. 

Notes
------
For 1.4.0 we never tested with deeper levels of graphs than two as shown above. If you try deeper nestings anything could happen! ;-)

Other documentation
===================

.. toctree::
   :maxdepth: 1

   protocol-multigraph.rst

