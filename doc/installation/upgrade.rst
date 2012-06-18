=================================
 Upgrading Munin from 1.x to 2.x
=================================

This is a compilation of items you need to pay attention to when
upgrading from Munin 1.x to munin 2.x

FastCGI
=======

Munin graphing is now done with FastCGI.

Munin HTML generation is optionally done with FastCGI.

Logging
=======

The web server needs write access to the munin-cgi-html and
munin-cgi-graph logs.
