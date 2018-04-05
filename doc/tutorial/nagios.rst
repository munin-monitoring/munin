.. _tutorial-nagios:

================
Munin and Nagios
================

Munin integrates perfectly with Nagios. There are, however,
a few things of which to take notice. This article shows example
configurations and explains the communication between the systems.

Setting up Nagios passive checks
================================

Receiving messages in Nagios
----------------------------

First you need a way for Nagios to accept messages from Munin.
Nagios has exactly such a thing, namely the NSCA which is documented here:
`NSCA <http://nagios.sourceforge.net/docs/nagioscore/3/en/addons.html#nsca>`_.

NSCA consists of a client (a binary usually named ``send_nsca`` and
a server usually run from ``inetd``. We recommend that you enable
encryption on NSCA communication.

You also need to configure Nagios to accept messages via NSCA.
NSCA is, unfortunately, not very well documented in Nagios'
official documentation. We'll cover writing the needed service check
configuration further down in this document.

Configuring Nagios
------------------

In the main config file, make sure that the ``command_file``
directive is set and that it works. See
`External Command File <http://nagios.sourceforge.net/docs/nagioscore/3/en/configmain.html#command_file>`_
for details.

Below is a sample extract from ``nagios.cfg``:

::

 command_file=/var/run/nagios/nagios.cmd

The ``/var/run/nagios`` directory is owned by the user nagios runs as.
The ``nagios.cmd`` is a named pipe on which Nagios accepts external input.


Configuring NSCA, server side
-----------------------------

NSCA is run through some kind of (x)inetd. 

Using inetd
++++++++++++

the line below enables NSCA listening on port 5667::

 5667            stream  tcp     nowait  nagios  /usr/sbin/tcpd  /usr/sbin/nsca -c /etc/nsca.cfg --inetd

Using xinetd
+++++++++++++

the lines below enables NSCA listening on port 5667, allowing connections only from the local host::

 # description: NSCA (Nagios Service Check Acceptor)
 service nsca
 {
  flags           = REUSE
  type    = UNLISTED
  port    = 5667
  socket_type     = stream
  wait            = no

  server          = /usr/sbin/nsca
  server_args     = -c /etc/nagios/nsca.cfg --inetd
  user            = nagios
  group           = nagios

  log_on_failure  += USERID

  only_from       = 127.0.0.1
 }

Common
+++++++

The file ``/etc/nsca.cfg`` defines how NSCA behaves.
Check in particular the ``nsca_user`` and ``command_file`` directives,
these should correspond to the file permissions and the
location of the named pipe described in ``nagios.cfg``.

::

 nsca_user=nagios
 command_file=/var/run/nagios/nagios.cmd


Configuring NSCA, client side
-----------------------------

The NSCA client is a binary that submits to an NSCA server whatever it
received as arguments. Its behaviour is controlled by the file
``/etc/send_nsca.cfg``, which mainly controls encryption.

You should now be able to test the communication between the NSCA client
and the NSCA server, and consequently whether Nagios picks up the message.
NSCA requires a defined format for messages. For service checks, it's like this:

::

 <host_name>[tab]<svc_description>[tab]<return_code>[tab]<plugin_output>[newline]

Below is shown how to test NSCA.

::

 $ echo -e "foo.example.com\ttest\t0\t0" | /usr/sbin/send_nsca -H localhost -c /etc/send_nsca.cfg
 1 data packet(s) sent to host successfully.


This caused the following to appear in ``/var/log/nagios/nagios.log``:

::

 [1159868622] Warning:  Message queue contained results for service 'test' on host 'foo.example.com'.  The service could not be found!


Sending messages from Munin
===========================

Messages are sent by :ref:`munin-limits <munin-limits>` based on the state of a monitored data source:
``OK``, ``Warning``, ``Critical`` and ``Unknown`` (O/W/C/U).

Configuring munin.conf
----------------------

Nagios uses the above mentioned ``send_nsca`` binary to send messages to Nagios.
In ``/etc/munin/munin.conf``, enter this:

::

 contacts nagios
 contact.nagios.command /usr/bin/send_nsca -H your.nagios-host.here -c /etc/send_nsca.cfg

.. note:: Be aware that the ``-H`` switch to ``send_nsca`` appeared sometime after ``send_nsca`` version 2.1. Always check ``send_nsca --help``!

Configuring Munin plugins
-------------------------

Lots of Munin plugins have (hopefully reasonable) values for
Warning and Critical levels. To set or override these,
you can change the values in :ref:`munin.conf <munin.conf>`.

Configuring Nagios services
---------------------------

Now Nagios needs to recognize the messages from Munin as messages
about services it monitors. To accomplish this, every message Munin
sends to Nagios requires a matching (passive) service defined or
Nagios will ignore the message (but it will log that something tried).

A passive service is defined through these directives in the proper Nagios configuration file:

::

 active_checks_enabled           0
 passive_checks_enabled          1


A working solution is to create a template for passive services, like the one below:

::

 define service {
         name                            passive-service
         active_checks_enabled           0
         passive_checks_enabled          1
         parallelize_check               1
         notifications_enabled           1
         event_handler_enabled           1
         register                        0
         is_volatile                     1
 }

When the template is registered, each Munin plugin should be registered as per below:

::

 define service {
         use                             passive-service
         host_name                       foo
         service_description             bar
         check_period                    24x7
         max_check_attempts              3
         normal_check_interval           3
         retry_check_interval            1
         contact_groups                  linux-admins
         notification_interval           120
         notification_period             24x7
         notification_options            w,u,c,r
         check_command                   check_dummy!0
 }

Notes
-----

- ``host_name`` is either the FQDN of the `host_name <http://munin-monitoring.org/wiki/host_name>`_
  registered to the Nagios plugin, or the host alias corresponding to Munin's
  `notify_alias <http://munin-monitoring.org/wiki/notify_alias>`_ directive.
  The ``host_name`` must be registered as a host in Nagios.

- ``service_description`` must correspond to the plugin's name, and for
  Nagios to be happy it shouldn't have any special characters.
  If you'd like to change the service description from Munin,
  use `notify_alias <http://munin-monitoring.org/wiki/notify_alias>`_
  on the data source. Available in Munin-1.2.5 and later.

A working example is shown below:

::

 [foo.example.com]
         address foo.example.com
         df.notify_alias Filesystem usage
         # The above changes from Munin's default "Filesystem usage (in %)"

**What characters are allowed in a Nagios service definition?**

 See Nagios docs on `Illegal Object Name Characters <http://nagios.sourceforge.net/docs/3_0/configmain.html#illegal_object_name_chars>`_

``service_description``: This directive is used to define the description of the service,
which may contain spaces, dashes, and colons (semicolons, apostrophes, and quotation
marks should be avoided). No two services associated with the same host
can have the same description. Services are uniquely identified with their host_name
and service_description directives.

.. note:: This means that lots of Munin plugins will not be accepted by Nagios.
   This limitation impacts every plugin with special characters in them,
   e.g. '(', ')', and '%'. Workarounds are described in
   `ticket #34 <http://munin-monitoring.org/ticket/34>`_ and the bug has been fixed
   in the Munin code in changeset 1081.

Alternatively you can use
`check_munin.pl <http://exchange.nagios.org/directory/Plugins/Uncategorized/Operating-Systems/Linux/check_munin_rrd/details>`_
to gather fresh data from nagios instead of check_dummy.


Sample munin.conf
=================

To illustrate, a (familiar) sample :ref:`munin.conf <munin.conf>` configuration file shows the usage:

::

 contact.nagios.command /usr/local/nagios/bin/send_nsca nagioshost.example.com -c /usr/local/nagios/etc/send_nsca.cfg -to 60

 contacts no                    # Disables warning on a system-wide basis.

 [example.com;]
   contacts nagios              # Enables warning through the "nagios" contact for the group example.com

 [foo.example.com]
   address localhost
   contacts no                  # Disables warning for all plugins on the host foo.example.com.

 [example.com;bar.example.com]
   address bar.example.com
   df.contacts no               # Disables warning on the df plugin only.
   df.notify_alias Disk usage   # Uses the title "Disk usage" when sending warnings through munin-limits
                                # Useful if the receiving end does not accept all kinds of characters
                                # NB: Only available in Munin-1.2.5 or with the patch described in ticket 34.

Setting up Nagios active checks
===============================

Use `check_munin.p <http://exchange.nagios.org/directory/Plugins/Uncategorized/Operating-Systems/Linux/check_munin_rrd/details>`_
to get data from munin-node directly into nagios and then use it as a regular check plugin.
Basically munin-node become a kind of snmp agent with a lot of preconfigured plugins.
