.. _example-transport-ssh:

==========================
Examples for ssh transport
==========================

.. index::
   triple: ssh transport; munin.conf; example

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
