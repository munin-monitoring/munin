.. _tutorial-snmp:

===================
Using SNMP plugins
===================

**Note:** Most of the information on this page is specific to SNMP plugins, but the first section (manually enabling SNMP plugins) applies to all remote monitoring plugins, not just SNMP.


Configuring the node
====================

In this example setup, both munin and munin-node run on the server "dumbledore", and we also want to monitor the router "netopia" using SNMP plugins. The setup is shown below:

.. image:: Munin-snmp-via-dumbledore.png

Manually enabling SNMP plugins
------------------------------

SNMP plugins are named with the format ``[protocol]__[metric]``, or ``[protocol]__[metric]_`` for wildcard plugins, e.g. ``snmp__if_`` for monitoring network interfaces or ``snmp__uptime`` for uptime.

To enable them, symlink them into ``/etc/munin/plugins`` on the node as normal, inserting the name of the host to be monitored between the first two underscores, e.g.

::

 ln -s snmp__if_ /etc/munin/plugins/snmp_netopia_if_1
 ln -s snmp__uptime /etc/munin/plugins/snmp_netopia_uptime


Using ``munin-node-configure``
------------------------------

The easy way to configure SNMP plugins in Munin is to use :ref:`munin-node-configure <munin-node-configure>`.

On the node you want to use as an SNMP gateway ("dumbledore"), run the configure script against your SNMP-enabled device ("netopia").

::

 dumbledore:~# munin-node-configure --shell --snmp netopia
 ln -s /usr/share/munin/plugins/snmp__if_ /etc/munin/plugins/snmp_netopia_if_1
 ln -s /usr/share/munin/plugins/snmp__if_err_ /etc/munin/plugins/snmp_netopia_if_err_1

This process will check each plugin in your Munin plugin directory for the :ref:`magic markers <magic-markers>` ``family=snmpauto`` and ``capabilities=snmpconf``, and then run each of these plugins against the given host or CIDR network.

Cut and paste the suggested ``ln`` commands and restart your node.

IPv6
----

To probe SNMP hosts over IPv6, use ``--snmpdomain udp6`` with ``munin-node-configure``. To have the SNMP plugins poll devices over IPv6, set the ``domain`` environment variable to ``udp6`` in the plugin configuration file. Other transports are available; see the ``Net::SNMP`` perldoc for more options.

Custom SNMP communities
-----------------------

``munin-node-configure`` accepts the ``--snmpcommunity`` flag (and ``--snmpversion``):

::

 munin-node-configure --shell \
   --snmp <host|cidr> \
   --snmpversion <ver> \
   --snmpcommunity <comm>

You also need to set the community for the plugins themselves, if it's different from the default ``public``. By convention this is done via the ``community`` environment variable. Configure this in ``/etc/munin/plugin-conf.d`` on the node, like any other plugin configuration.

Example file ``/etc/munin/plugin-conf.d/snmp_communities``:

::

 [snmp_netopia_*]
 env.community seacrat community

 [snmp_some.other.device_*]
 env.community frnpeng pbzzhavgl

Always provide your community name unquoted. In fact, if you do quote it, it will treat the quote as part of the community name, and that will usually not work. Just note that any prefix or trailing white space is stripped out, so you **cannot** currently configure a community name with a prefix or trailing white space.

Checking your configuration
---------------------------

If the plugins are configured properly, the node will present multiple virtual nodes when queried:

::

 dumbledore:~# telnet localhost 4949
 Trying 127.0.0.1...
 Connected to localhost.
 Escape character is '^]'.
 # munin node at dumbledore
 nodes
 netopia
 dumbledore
 .
 list netopia
 snmp_netopia_if_1
 snmp_netopia_if_err_1


Configuring the master with ``munin.conf``
==========================================

On the master, you add an entry for the hosts monitored by the SNMP plugins the same way you add any other node; however, you need to set the ``address`` to the address of the node the plugins run on -- not the address of the system being monitored -- and turn off ``use_node_name``.

For the above setup, :ref:`munin.conf <munin.conf>` would look like this:

::

 [dumbledore]
    address localhost
    use_node_name yes

 [netopia]
    address localhost
    use_node_name no

(``use_node_name`` is somewhat confusingly named; if **true**, it means to use the name of the node the master is connecting to as the name of the node to collect metrics for, in this case ``dumbledore``. If **false**, it means to ignore the name of the node itself, and instead collect metrics based on the name of that section in the config file, in this case ``netopia``.)
