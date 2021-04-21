.. _munin-cgi-graph:

.. program:: munin-cgi-graph

=================
 munin-cgi-graph
=================

DESCRIPTION
===========

The munin-cgi-graph program is intended to be run from a web server.
It can either run as CGI, or as FastCGI.

OPTIONS
=======

munin-cgi-graph is controlled using environment variables. See
environment variables :envvar:`PATH_INFO` and :envvar:`QUERY_STRING`.

Note: The munin-cgi-graph script may be called with the command line
options of :ref:`munin-graph`. However, the existence of this should
not be relied upon.

ENVIRONMENT VARIABLES
=====================

The following environment variables are used to control the output of
munin-cgi-graph:

.. envvar:: PATH_INFO

   This is the remaining part of the URI, after the path to the
   munin-cgi-graph script has been removed.

   The group, host, service and timeperiod values are extracted from
   this variable. The group may be nested.

.. envvar:: CGI_DEBUG

   If this variable is set, debug information is logged to STDERR, and
   to /var/log/munin/munin-cgi-graph.log

.. envvar:: QUERY_STRING

   A list of key=value parameters to control munin-cgi-graph. If
   QUERY_STRING is set, even to an empty value, a no_cache header is
   returned.

.. envvar:: HTTP_CACHE_CONTROL

   If this variable is set, and includes the string "no_cache", a
   no_cache header is returned.

.. envvar:: HTTP_IF_MODIFIED_SINCE

   Returns 304 if the graph is not changed since the timestamp in the
   HTTP_IF_MODIFIED_SINCE variable.

EXAMPLES
========

When given an URI like the following:

http://munin/munin-cgi/munin-cgi-graph/example.org/client.example.org/cpu-week.png

munin-cgi-graph will be called with the following environment:

PATH_INFO=/example.org/client.example.org/cpu-week.png

To verify that munin is indeed graphing as it should, you can use the
following command line:

.. code-block:: bash

   sudo -u www-data \
   PATH_INFO=/example.org/client.example.org/irqstats-day.png \
   /usr/lib/munin/cgi/munin-cgi-graph | less

The "less" is strictly not needed, but is recommended since
munin-cgi-graph will output binary data to your terminal.

You can add the :envvar:`CGI_DEBUG` variable, to get more log
information. Content and debug information is logged to STDOUT and
STDERR, respectively. If you only want to see the debug information,
and not the HTTP headers or the content, you can redirect the file
descriptors:

.. code-block:: bash

   sudo -u www-data \
   CGI_DEBUG=yes \
   PATH_INFO=/example.org/client.example.org/irqstats-day.png \
   /usr/lib/munin/cgi/munin-cgi-graph 2>&1 >/dev/null | less

SEE ALSO
========

See :ref:`munin` for an overview over munin.
