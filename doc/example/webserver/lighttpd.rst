.. _example-webserver-lighttpd:

========================
 lighttpd configuration
========================

This example describes how to set use lighttpd in front of
munin-httpd.

Webserver configuration
=======================

.. index::
   triple: example; lighttpd configuration; munin-httpd

::

  alias.url += ( "/munin-static" => "/etc/munin/static" )
  alias.url += ( "/munin"        => "/var/cache/munin/www/" )

  $HTTP["url"] =~ "^/munin" {
    proxy.server = (""    => (( "host" => "127.0.0.1", "port" => 4948)))
  }
