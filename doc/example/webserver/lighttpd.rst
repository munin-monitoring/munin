.. _example-webserver-lighttpd:

========================
 lighttpd configuration
========================

This example describes how to set use lighttpd in front of
munin-httpd.

Munin configuration
===================

This example assumes the following configuration in
/etc/munin/munin.conf

.. index::
   pair: example; munin.conf
   pair: example; html_strategy
   pair: example; graph_strategy

::

   html_strategy cgi
   graph_strategy cgi

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
