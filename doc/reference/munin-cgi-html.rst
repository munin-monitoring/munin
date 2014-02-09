.. _munin-cgi-html:

.. program:: munin-cgi-html

================
 munin-cgi-html
================

DESCRIPTION
===========

The :program:`munin-cgi-html` program is intended to be run from a
web server. It can either run as CGI, or as FastCGI.

OPTIONS
=======

munin-cgi-html takes no options. It is controlled using environment
variables.

ENVIRONMENT VARIABLES
=====================

The following environment variables are used to control the output of
munin-cgi-html:

.. envvar:: PATH_INFO

   This is the remaining part of the URI, after the path to the
   munin-cgi-html script has been removed.

   The group, host, service and timeperiod values are extracted from
   this variable. The group may be nested.

EXAMPLES
========

PATH_INFO
---------

"/"
     refers to the top page.

"/example.com/"
     refers to the group page for "example.com" hosts.

"/example.com/client.example.com/"
     refers to the host page for "client.example.com" in the
     "example.com" group

COMMAND-LINE
------------

When given an URI like the following:
http://munin.example.org/munin-cgi/munin-cgi-html/example.org

munin-cgi-html will be called with the following environment:

PATH_INFO=/example.org

To verify that munin is able to create HTML pages, you can use the
following command line:

.. code-block:: bash

   sudo -u www-data \
   PATH_INFO=/example.org \
   /usr/lib/munin/cgi/munin-cgi-html

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin-cgi-graph`.
