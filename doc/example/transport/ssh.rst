.. _example-transport-ssh:

==========================
Examples for ssh transport
==========================

Using the ssh transport for munin is a very powerful way to reach hard to reach nodes in a secure and well understood way.

.. index::
   triple: ssh transport; munin.conf; example
   
Using SSH transport
===================

For a host that you can only reach via ssh (because firewall, or because you don't want to expose munin-node on the network, only to localhost) Munin can use SSH directly like this:

  [mail.site2.example.org]
     address ssh://mail.site2.example.org -W localhost:4949
     
This makes munin use the ssh terminal connection as a network socket.  The "address" line bunces the ssh terminal connection to the munin-node port on the remote host.

If you can reach the node via some bastion or bounce host a similar command can be used:

  [mail.site2.example.org]
     address ssh://bastion.site2.example.org -W mail.site2.example.org:4949
     
This will make munin first ssh into bastion.site2.example.org, and then from there connect the munin-node port (4949) on mail.site2.example.org.

You will need to configure ssh to allow these connections.


SSH options
===========

Options for the ssh\:// transport can be added to `.ssh/config` in the
home directory of the munin user.

The available options are available with `man ssh_config`. Here are
some examples.

Compression
-----------

SSH has the option of compressing the data transport.  To add
compression to all SSH connections::

  Host *
    Compression yes

If you have a lot of nodes, you will reduce data traffic by spending
more CPU time.  See also the CompressionLevel setting from the
`ssh_config` man page.


Connecting through a Proxy
--------------------------

By using the `ProxyCommand` SSH option, you can connect with ssh via a
jump host, and reach :ref:`munin-node` instances which are not
available directly from the munin master::

   Host *.customer.example.com !proxy.customer.example.com
   ProxyCommand ssh -W %h:%p proxy.customer.example.com

This will make all connections to host ending with
.customer.example.com, connect through proxy.customer.example.com,
with an exemption for the proxy host itself.

Note: If you use `Compression`, try not to compress data twice.
Disable compression for the proxied connections with `Compression no`.


Re-using SSH connections
------------------------

If you connect to a host often, you can re-use the SSH connection
instead. This is a good example to combine with the `Connecting
through a proxy` and the `Compression` examples::

  Host proxy.customer.example.com
   ControlMaster       auto
   ControlPath         /run/munin/ssh.%h_%p_%r
   ControlPersist      360
   TCPKeepAlive        yes
   ServerAliveInterval 60

This will keep a long-lived SSH connection open to
`proxy.customer.example.com`, it will be re-used for all
connections. The SSH options `TCPKeepAlive` and `ServerAliveInterval`
are added to detect and restart a dropped connection on demand.


