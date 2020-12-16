.. _node-async:

=========================
 Asynchronous proxy node
=========================

Context
=======

We already discussed that munin-update is the fragile link in the munin
architecture. A missed execution means that some data is lost.

The problem : updates are synchronous
-------------------------------------

In Munin 1.x, updates are synchronous : the epoch and value in each
service are the ones munin-update retrieves each scheduled run.

The issue is that munin-update has to ask every service on every node
every run for their values. Since the values are only computed when
asked, munin-update has to wait quite some time for every value.

This design is very simple, it therefore enables munin to have the
simplest plugins since they are completely stateless. While being the
greatest strength of munin, it still puts a severe blow on scalability
: more plugins and/or nodes means obviously a slower retrieval.

Evolving Solution : Parallel Fetching
--------------------------------------

1.4 addresses some of these scalability issues by implementing parallel
fetching. It takes into account that the most of the execution time of
munin-update is spent waiting for replies.

Note that there is the max_processes configuration parameter that
control how many nodes in parallel munin-update can ask.

Now, the I/O part is becoming the next limiting factor, since updating
many RRD files in parallel means massive and completely random I/O for
the underlying munin-master OS.

Serializing & grouping the updates is possible with the rrdcached
daemon from rrdtool starting at 1.4 and on-demand graphing. This looks
very promising, but doesn't address the root defect in this design : a
hard dependence of regular munin-update runs. And upon close analysis,
we can see that 1.4 isn't ready for rrdcached as it asks for flush each
run, in munin-limits.


2.0 : Stateful plugins (supersampling)
--------------------------------------

2.0 provides a way for plugins to be stateful. They might schedule
their polling themselves, and then when munin-update runs, only emit
collect already computed values. This way, a missed run isn't as
dramatic as it is in the 1.x series, since data isn't lost. The data
collection is also much faster because the real computing is done ahead
of time. This behavior is called supersampling.

2.0 : Asynchronous proxy node
-----------------------------

But changing plugins to be self-polled is difficult and tedious. It
even works against of one of the real strength of munin : having very
simple, therefore stateless, plugins.

To address this concern, a proxy node was created. For 2.0 it takes
the form of 2 tools : munin-asyncd and munin-async.

The proxy node in detail (munin-async)
--------------------------------------

Overview
++++++++

These 2 processes form an asynchronous proxy between munin-update and
munin-node. This avoids the need to change the plugins or upgrade
munin-node on all nodes.

munin-asyncd should be installed on the same host than the proxied
munin-node in order to avoid any network issue. It is the process
that will poll regularly munin-node. The I/O issue of munin-update is
here non-existent, since munin-async stores all the values by plainly
appending them in text files without any processing. The files are
defined as one per plugin, rotated per a timeframe.

These files are later read by munin-async client part that is
typically accessed via ssh from munin-update. Here again no fancy
processing is done, just plainly read back to the calling
munin-update to be processed there. This way the overhead on the node
is minimal.

The nice part is that the munin-async client does not need to run on
the node, it can run on a completely different host. All it takes is
to synchronize the spoolfetch dir. Sync can be periodic (think rsync)
or real-time (think NFS).

In the same idea, the munin-asyncd can also be hosted elsewhere for
disk-less nodes.

Specific update rates
+++++++++++++++++++++

Having one proxy per node enables a polling of all the services there
with a plugin specific update rate.

To achieve this, munin-asyncd optionally forks into multiple
processes, one for each plugin. This way each plugin is completely
isolated from others. It can set its own update_rate, it is isolated
from other plugins slowdowns, and it does even completely parallelize
the information gathering.

SSH transport munin-async-client uses the new SSH native transport of
2.0. It permits a very simple install of the async proxy.

Notes
*****

In 1.2 a service is the same as plugin, but since 1.4 and the
introduction of multigraph, one plugin can provide multiple services.
Think it as one service, one graph.

Installation
============

munin-async is a helper to poll regularly


The munin asynchronous proxy node (or "munin-asyncd") connects to the
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
"ssh\://" address and append the command to execute to the ssh address.

Make sure the /usr/local/bin/munin-async path exists on the targeted address,
the path might be different depending on the distribution used.

Port 22 was added on purpose as an example but can be left from the address
since port 22 is the default for ssh.

::

  [random.example.org]
    address ssh://munin-async@random.example.org:22/usr/local/bin/munin-async --spoolfetch --spooldir /var/lib/munin/spool

You will need to create an SSH key for the "munin" user on the master,
and distribute the public key to the specified node defined in the config.

The ssh command and options can be customized in :ref:`munin.conf`
with the ssh_command and ssh_options configuration options. The following will
point to an alternate location for an ssh user config and id_rsa.
(needed in case /var/lib/munin isn't the home dir for munin on the master node)

::

  ssh_options -F /var/lib/munin/.ssh/config -i /var/lib/munin/.ssh/id_rsa

A possible configuration could be to add an ssh config, and save the
rsa key on the munin home directory.

::

  cat <<EOF > /var/lib/munin/.ssh_async/config
  Host *
    BatchMode=yes
    ConnectTimeout=5
    EscapeChar=none
    ExitOnForwardFailure=yes
    ForwardAgent=no
    ForwardX11=no
    IdentitiesOnly=yes
    PasswordAuthentication=no
    RequestTTY=no
    StrictHostKeyChecking=no
    PreferredAuthentications=publickey
    User munin-async
  EOF

It's also possible to add UserKnownHostsFile=/dev/null to the above config
if you don't care that the monitor host can be reinstalled,
so you will not need to cleanup the host in known_hosts file.

On the munin node
-----------------

Configure your munin node to only listen on "127.0.0.1".

You will also need to add the public key of the munin user to the
authorized_keys file for this munin-async user.

Make sure that the munin-async user has his home configured
to the /var/lib/munin/spool dir.

Make sure munin-asyncd is running and populates the /var/lib/munin/spool directory.
The default options for munin-asyncd is to have a sample size of 86400 which
would better be set to a lower value in case plugins could generate big spool files
(>20MB). Eg a value of 3600 would result in smaller files resulting in incremental
updates over multiple updates in case of a big backlog (eg: munin master couldn't
connect for a few days). If you want to keep a big backlog, then you might want
to increase the retain option for the amount of samples to keep.

The following options are recommended for security, but are strictly
not necessary for the munin-async connection to work

 * You should add hardening options. At the time of writing, these are
   "no-X11-forwarding", "no-agent-forwarding", "no-port-forwarding",
   "no-pty" and "no-user-rc".

   Some of these may also be set globally in /etc/ssh/sshd_config
   or the ~/.ssh/config for the munin-async user.

See the sshd_config (5) and authorized_keys(5) man pages for more information.

Trouble shooting
----------------

1. Check if munin-asyncd populates the spool dir, a file (or files) per plugin should be seen.
2. Check if the munin master node can connect to the node to be monitored. Check the logs of ssh!
   If the munin-async user doesn't have a password, the user might not be locked, and ssh could
   prevent to connect to such a user.
