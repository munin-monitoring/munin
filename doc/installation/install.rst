.. _installation:

==================
 Installing Munin
==================

Due to :ref:`Munin's Architecture <architecture-index>` you have to
install two different software packages depending on the role,
that the machine will play.

You will need to install "munin-master" on the machine that will
collect data from all nodes, and graph the results. When starting with
Munin, it should be enough to install the Munin master on one server.

The munin master runs :ref:`munin-httpd` which is a basic webserver
which provides the munin web interface on port 4948/tcp.

Install "munin-node" on the machines that shall be monitored by Munin.


Source or packages?
===================

With open source software, you can choose to install binary packages
or install from source-code.

.. note::

	We `strongly` recommend a packaged install, as the source distribution
	isn't as tested as the packaged one. The current state of the packages
	is so satisfactory, that even the developers use them instead.

Installing Munin on most relevant operating systems can usually be
done with the systems package manager, typical examples being:

Installing Munin from a package
===============================

FreeBSD
-------

From source:

.. code-block:: bash

 cd /usr/ports/sysutils/munin-master && make install clean
 cd /usr/ports/sysutils/munin-node && make install clean

Binary packages:

.. code-block:: bash

 pkg install munin-master
 pkg install munin-node

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

Current versions are available at `EPEL <https://fedoraproject.org/wiki/EPEL#What_packages_and_versions_are_available_in_EPEL.3F>`_.

In order to install Munin type

.. code-block:: bash

   sudo yum install munin-node

on all nodes, and

.. code-block:: bash

   sudo yum install munin

on the master.

You will have to enable the services in systemd to get them up and running.

Likely you will have to fix SELinux issues when using 3rd-Party plugins and SELinux active and set to *enforcing mode* on the Munin node.
In case you get competent and friendly support on `SELinux mailinglist <https://admin.fedoraproject.org/mailman/listinfo/selinux>`_.

Other systems
-------------

On other systems, you are probably best off compiling your own code.
See `Installing Munin from source`_.

Installing Munin from source
============================

.. warning::

	Usually you don't want to do that. The following lines are for
	completeness, and reference for packagers.

	The other reason would be because you want to contribute to the
	development of Munin, and then you should use a development install.

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
node and plugins on the nodes.

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
