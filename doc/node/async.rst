.. _node-async:

=========================
 Asynchronous proxy node
=========================

The munin asynchronous proxy node (or "munin-async") connects to the
local node periodically, and spools the results.

When the munin master connects, all the data is available instantly.

munin-asyncd
============

The Munin async daemon starts at boot, and connects to the local
munin-node periodically, like a :ref:`munin master <master-index>`
would. The results are stored the results in a spool, tagged with
timestamp.

You can also use munin-asyncd to connect to several munin nodes. You
will need to use one spooldir for each node you connect to. This
enables you to set up a "fanout" setup, with one privileged node per
site, and site-to-site communication being protected by ssh.

munin-async
===========

The Munin async client is invoked by the connecting master, and reads
from the munin-async spool using the "spoolfetch" command.

Example configuration
=====================

On the munin master
-------------------

We use ssh encapsulated connections with munin async. In the :ref:`the munin
master <master-index>` configuration you need to configure a host with a
"ssh\://" address.

::

  [random.example.org]
    address ssh://munin-async@random.example.org

You will need to create an SSH key for the "munin" user, and
distribute this to all nodes running munin-asyncd.

The ssh command and options can be customized in :ref:`munin.conf`
with the ssh_command and ssh_options configuration options.

On the munin node
-----------------

Configure your munin node to only listen on "127.0.0.1".

You will also need to add the public key of the munin user to the
authorized_keys file for this user.

 * You must add a "command=" parameter to the key to run the command
   specified instead of whatever command the connecting user tries to
   use.

::

  command="/usr/share/munin/munin-async --spoolfetch" ssh-rsa AAAA[...] munin@master

The following options are recommended for security, but are strictly
not necessary for the munin-async connection to work

 * You should add a "from=" parameter to the key to restrict where it
   can be used from.

 * You should add hardening options. At the time of writing, these are
   "no-X11-forwarding", "no-agent-forwarding", "no-port-forwarding",
   "no-pty" and "no-user-rc".

   Some of these may also be set globally in /etc/ssh/sshd_config.

::

  no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty,no-user-rc,from="192.0.2.0/24",command="/usr/share/munin/munin-async --spoolfetch" ssh-rsa AAAA[...] munin@master

See the sshd_config (5) and authorized_keys(5) man pages for more information.
