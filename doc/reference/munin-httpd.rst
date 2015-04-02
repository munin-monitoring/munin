.. _munin-httpd:

.. program:: munin-httpd

=============
 munin-httpd
=============

DESCRIPTION
===========

munin-httpd is a basic webserver.  It provides a munin web interface
on port 4948/tcp, generating pages and graphs on demand.

If this is used, :option:`html_strategy` and :option:`graph_strategy`
should both be set to "cgi" to prevent :ref:`munin-graph` and
:ref:`munin-update` from generating static graphs and pages.

If transport layer security and authentication is desired, place a
webserver with those features as a reverse proxy in front of
munin-httpd.

munin-httpd replaces munin-cgi-graph and munin-cgi-html.

OPTIONS
=======

munin-httpd takes no options.

CONFIGURATION
=============

munin-httpd reads its configuration from :ref:`munin.conf`.

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin-graph`, :ref:`munin-html`, :ref:`munin.conf`
