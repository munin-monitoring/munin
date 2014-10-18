Getting Started
================

Please refer to the :ref:`Nomenclature part <nomenclature>` to understand the terms used in this guide.

Installation
------------

Before you can use Munin you need to install it, of course. It is possible that
Munin is already installed at your site, either because it was included in your
operating system distribution or because the system administrator already
installed it. If that is the case, you should obtain information from the
operating system documentation or your system administrator about how to access
Munin.

If you are installing Munin yourself, then refer to :ref:`Install Chapter <installation>` 
for instructions on installation, and return to this guide when the installation is
complete. Be sure to follow closely the section about setting up the
appropriate configuration files.

All the tutorial will assume a Debian installation, so all the commands are
suited to the Debian package management system. As the one in Ubuntu is mostly
the same, examples should work unchanged. For RPM-based systems, the equivalent
yum command is left as an exercise to the reader, but should not be very hard
to get.

We cannot speak about every other OS, but any UNIX-like have been reported to
work. Your safest best should still to stick to a supported OS if you don't
feel adventurous.

Also, you should need a dedicated server for the master role, as it mostly
requires root access. Again, it is not required, but safety, and ability to
copy/paste the samples, advise you to stick to these guidelines.

Architectural Fundamentals
--------------------------
Munin has a master-nodes architecture. See :ref:`Munin's Architecture <architecture-index>` 
for the details.

.. image:: Munin-Architecture.png


Adding a Node
-------------

Thanks to the plug-and-play architecture of Munin, this is very easy. You
obviously have to install the node part on the host you want to monitor.

::

  $ apt-get install munin-node

This will install the node, some default plugins and launch it.

As the node runs as the root user in order to run plugins as any needed user,
it now only listens on localhost as a security measure. You have to edit
munin-node.conf in order to listen to the network, and add the master's IP on
the authorized list.

And don't forget to install munin-node also on the "Munin master" machine 
to monitor Munin's activities :-)
