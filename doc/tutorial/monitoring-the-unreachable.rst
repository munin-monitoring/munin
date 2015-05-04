.. _unreachable-index:

==================================
Monitoring the "unreachable" hosts
==================================



There are a number of situations where you'd like to run munin-node
on hosts not directly available to the Munin server.
This article describes a few scenarios and different alternatives
to set up monitoring. Monitoring hosts behind a non-routing server.

In this scenario, a \*nix server sits between the Munin server and
one or more Munin nodes. The server in-between reaches both the
Munin server and the Munin node, but the Munin server does not
reach the Munin node or vice versa.

To enable for Munin monitoring, there are several approaches,
but mainly either using SSH tunneling or "bouncing" via the in-between server.


SSH tunneling
-------------

The illustration below shows the principle. By using
SSH tunneling only one SSH connection is required,
even if you need to reach several hosts on "the other side".
The Munin server listens to different ports on the localhost interface.
A `configuration example <http://munin-monitoring.org/wiki/MuninConfigurationNetworkTunneling>`_
is included. Note that there is also a
`FAQ entry on using SSH <http://munin-monitoring.org/wiki/faq#Q:HowcanIuseanSSHtunneltoconnecttoanode>`_
that contains very useful information.

.. image:: MuninSSHForwarding.png

Bouncing
--------

This workaround uses netcat and inetd/xinetd to forward the queries
from the Munin server. All incoming connections to defined ports
are automatically forwarded to the Munin node using netcat.

.. image:: MuninPortForwarding.png

Behind a NAT device
-------------------

Monitoring hosts behind a NAT device (e.g. DSL router or firewall)

If you have one or more Munin nodes on the "inside" of a NAT device,
port forwarding is probably the easiest way to do it.
Configuring port forwarding on all kinds of network units and
firewall flavours is way beyond the scope of the Munin documentation,
but the illustration below show the principle.
A `sample configuration <http://munin-monitoring.org/wiki/MuninPortForwarding>`_
including munin.conf is found here.

Note that if the NAT device is a \*nix system,
you may also use the two approaches described above.

.. image:: MuninPortForwarding.png
