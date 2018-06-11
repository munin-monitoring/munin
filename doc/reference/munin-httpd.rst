.. _munin-httpd:

.. program:: munin-httpd

=============
 munin-httpd
=============

DESCRIPTION
===========

munin-httpd is a basic webserver.  It provides a munin web interface
on port 4948/tcp, generating pages and graphs on demand.

If transport layer security and authentication is desired, place a
webserver with those features as a reverse proxy in front of
munin-httpd.

munin-httpd was introduced after the 2.0.x release series.
It replaces the FastCGI scripts munin-cgi-graph and
munin-cgi-html, that were used in munin 2.0.

OPTIONS
=======

munin-httpd takes no options.

CONFIGURATION
=============

munin-httpd reads its configuration from :ref:`munin.conf`.

SEE ALSO
========

See :ref:`munin` for an overview over munin.

:ref:`munin.conf`
