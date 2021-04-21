==================
 Installing munin
==================

First: Please consider using a packaged version.  Munin is available
as packages in the packaging system of many operating systems.


To install munin in /usr/local, install its `build requirements`, and
then run:

.. code-block:: bash

   make
   make test
   # run as root or use something like "sudo"
   make install


This will install munin master, node and plugins.

For more information about requirements, please see the `install
documentation`_ (online) or the files in this repository below ``doc/installation/``.

.. _`build requirements`: http://guide.munin-monitoring.org/en/latest/installation/prerequisites.html
.. _`install documentation`: http://guide.munin-monitoring.org/en/latest/installation/
