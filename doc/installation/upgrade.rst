.. _upgrade:

===============
 Upgrade Notes
===============

Upgrading Munin from 2.0.x to 2.1.x
===================================

Munin HTTPD
-----------

:ref:`munin-httpd` replaces FastCGI.  It is a basic webserver capable
of serving pages and graphs.

To add transport layer security or authentication, use a webserver
with more features as a proxy.

If you choose to use :ref:`munin-httpd`, set :option:`graph_strategy`
and :option:`html_strategy` to "cgi".

FastCGI
-------

…is gone.  It was hard to set up, hard to debug, and hard to support.

Upgrading Munin from 1.x to 2.x
===============================

This is a compilation of items you need to pay attention to when
upgrading from Munin 1.x to munin 2.x

FastCGI
-------

Munin graphing is now done with FastCGI.

Munin HTML generation is optionally done with FastCGI.

Logging
-------

The web server needs write access to the munin-cgi-html and
munin-cgi-graph logs.
