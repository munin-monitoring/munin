.. _example-webserver-lighttpd-proxy:

==============================
 lighttpd Proxy Configuration
==============================

This example describes how to use `lighttpd <http://lighttpd.org>`_ in front of :ref:`munin-httpd`.


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
