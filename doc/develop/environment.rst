.. _develop-environment:

===============================
 Munin development environment
===============================

Getting started
===============

#. Install perl
#. Check out the munin repository
#. Install perl dependencies
#. Install munin in a sandbox
#. Start munin in a sandbox
#. Start hacking


Install perl
============

You need ``perl 5.10`` or newer for munin development.  Check your
installed version with ``perl --version``.

If you have an older perl, look at using ``perlbrew`` to have perl in
a sandbox.

Check out the munin repository
==============================

Munin is hosted on github.  Clone the git repository, and enter the
work directory.

.. code-block:: bash

   git clone https://github.com/munin-monitoring/munin
   cd munin

Install perl dependencies
=========================

Munin needs a lot of perl modules.  The dependencies needed to
develop, test, build and run munin is listed in the ``Build.PL`` file.

With the Debian osfamily
------------------------

This includes Debian, Ubuntu, and many other operating systems.

Dependencies for running Munin from the development environment.

.. code-block:: bash

   apt install libdbd-sqlite3-perl libdbi-perl \
       libfile-copy-recursive-perl libhtml-template-perl \
       libhtml-template-pro-perl libhttp-server-simple-perl \
       libio-socket-inet6-perl liblist-moreutils-perl \
       liblog-dispatch-perl libmodule-build-perl libnet-server-perl \
       libnet-server-perl libnet-snmp-perl librrds-perl \
       libnet-ssleay-perl libparams-validate-perl liburi-perl \
       libwww-perl libxml-dumper-perl

Dependencies for running the Munin development tests:

.. code-block:: bash

   apt install libdbd-pg-perl libfile-readbackwards-perl \
       libfile-slurp-perl libio-stringy-perl libnet-dns-perl \
       libnet-ip-perl libtest-deep-perl libtest-differences-perl \
       libtest-longstring-perl libtest-mockmodule-perl \
       libtest-mockobject-perl libtest-perl-critic-perl \
       libxml-libxml-perl libxml-parser-perl

With modules from CPAN
----------------------

.. code-block:: bash

   perl Build.PL
   ./Build installdeps

Install munin in a sandbox
==========================

The ``dev_scripts`` directory contains scripts to install munin in a
sandbox.  We also need to disable ``taint`` in the perl scripts to
enable it to run outside the normal perl installation.

.. code-block:: bash

   dev_scripts/install node
   dev_scripts/disable_taint

Run munin in a sandbox
======================

Each of these can be done in a separate terminal window, to keep the
logs apart.

Start a munin node.  This will start the node in the background, and
tail the log. If you hit Ctrl-C, the log tailing will stop, and the
node will still run in the background.

.. code-block:: bash

   dev_scripts/start_munin-node

The ``contrib`` directory contains a daemon used for simulating a lot
of munin nodes.  This step is optional.  First output a number of node
definitions to the munin configuration, and then run the daemon in the
background.

.. code-block:: bash

   contrib/munin-node-debug -d  > sandbox/etc/munin-conf.d/nodes.debug
   contrib/munin-node-debug &

Start a munin-update loop.  Normally, munin-update runs from cron
every 5 minutes.

.. code-block:: bash

   while :; do dev_scripts/run munin-update; sleep 60; done &

The munin httpd listens on http://localhost:4948/ by default.

.. code-block:: bash

   dev_scripts/run munin-httpd

Start hacking
=============

Make changes, restart sandboxed services as necessary.

Make a git feature branch, commit changes, publish branch to a public
git repository somewhere, submit pull requests, make things happen.
