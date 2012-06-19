==================
 Installing Munin
==================

With open source software, you can choose to install binary packages
or install from source-code. To install a package or install from
source is a matter of personal taste. If you don't know which method
too choose read the whole document and choose the method you are most
comfortable with.

Master and node
===============

Munin is split into two distinct roles.

Node
----

The "munin node" is a daemon which runs on all servers being
monitored.


Master
------

The "munin master" connects to all munin nodes, collects data, and
stores it in `RRD <http://oss.oetiker.ch/rrdtool/>`_

You will need to install "munin-master" on the server which will
collect data from all nodes, and graph the results. When starting with
munin, it should be enough to install the munin master on one server.

On the munin master, you will need a web server capable of running CGI
or FastCGI. Apache HTTD should be suitable. Also reported to be
working is nginx and lighttpd.

Source or packages?
===================

Installing Munin on most relevant operating systems can usually be
done with with the systems package manager, typical examples being:

FreeBSD
-------

From source:

.. code-block:: bash

 cd /usr/ports/sysutils/munin-master && make install clean
 cd /usr/ports/sysutils/munin-node && make install clean

Binary packages:

.. code-block:: bash

 pkg_add -r munin-master
 pkg_add -r munin-node

Debian/Ubuntu
-------------

Munin is distributed with both Debian and Ubuntu.

In order to get Munin up and running type

.. code-block:: bash

 sudo apt-get install munin-node

on all nodes, and

.. code-block:: bash

 sudo apt-get install munin

on the master.

Please note that this might not be the latest version of Munin. On
Debian you have the option of enabling "backports", which may give
access to later versions of Munin.

RedHat / CentOS / Fedora
------------------------

At time of writing, only the 1.x version of munin is available in
`EPEL
<http://dl.fedoraproject.org/pub/epel/6/SRPMS/repoview/munin.html>`_.

If you want 2.x, your best option is probably to install from source.

Other systems
-------------

On other systems, you are probably best off compiling your own code.
See `Installing Munin from source`_.

Installing Munin from source
============================

If there are no binary packages available for your system, or if you
want to install Munin from source for other reasons, follow these
steps:

We recommend downloading a release tarball, which you can find on
`sourceforge.net <http://sourceforge.net/projects/munin/files/stable/>`_.

Alternatively, if you want to hack on Munin, you should clone our git
repository by doing.

.. code-block:: bash

 git clone git://github.com/munin-monitoring/munin

Please note that a git checkout will need some more build-dependencies
than listed below, in particular the Python Docutils and Sphinx.

Build dependencies on Debian / Ubuntu
-------------------------------------

In order to build Munin from source you need a number of packages
installed. On a Debian or Ubuntu system these are:

* perl
* htmldoc
* html2text
* default-jdk

Configuring and installing
--------------------------

Warning for NFS users
~~~~~~~~~~~~~~~~~~~~~

If you're using NFS please note that the "make install" process is
slightly problematic in that it (Module::Build actually) writes files
under $CWD. Since "make install" is usually run by root and root
usually cannot write files on a NFS volume, this will fail. If you use
NFS please install munin from /var/tmp, /tmp or some such to work
around this.

Running make
~~~~~~~~~~~~

There are make targets for node, master, documentation and man files.
Generally you want to install everything on the master, and just the
node and plugiuns on the nodes.

- Edit Makefile.config to suit your needs.

- Create the user "munin" with the primary group "munin".

  The user needs no shell and no privileges. On most Linux systems the
  munin user's shell is the nologin shell (it has different paths on
  different systems - but the user still needs to be able to run cron
  jobs.

Node
~~~~

For the node, you need only the common parts, the node and the plugins.

.. code-block:: bash

 make
 make install-common-prime install-node-prime install-plugins-prime


Master
~~~~~~

For the master, this will install everything.

.. code-block:: bash

 make
 make install
