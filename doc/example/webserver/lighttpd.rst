.. _example-webserver-lighttpd:

========================
 lighttpd configuration
========================

This example describes how to set up munin on lighttpd. It spawns two
lighttpd processes, one for the graph rendering, and one for the html
generation.

You need to enable the "mod_rewrite" module in the main lighttpd
configuration.

Munin configuration
===================

This example assumes the following configuration in
/etc/munin/munin.conf

.. index::
   pair: example; munin.conf

::

 # graph_strategy should be commented out, if present
 html_strategy cgi

Webserver configuration
=======================

.. index::
   pair: example; lighttpd configuration

::

  alias.url += ( "/munin-static" => "/etc/munin/static" )
  alias.url += ( "/munin"        => "/var/cache/munin/www/" )

  fastcgi.server += ("/cgi-bin/munin-cgi-graph" =>
                     (( "socket"      => "/var/run/lighttpd/munin-cgi-graph.sock",
                        "bin-path"    => "/usr/lib/cgi-bin/munin-cgi-graph",
                        "check-local" => "disable",
                     )),
                    "/cgi-bin/munin-cgi-html" =>
                     (( "socket"      => "/var/run/lighttpd/munin-cgi-html.sock",
                        "bin-path"    => "/usr/lib/cgi-bin/munin-cgi-html",
                        "check-local" => "disable",
                     ))
                   )

  url.rewrite-repeat += (
                     "/munin/(.*)" => "/cgi-bin/munin-cgi-html/$1",
                     "/cgi-bin/munin-cgi-html$" => "/cgi-bin/munin-cgi-html/",
                     "/cgi-bin/munin-cgi-html/static/(.*)" => "/munin-static/$1"
                     )
