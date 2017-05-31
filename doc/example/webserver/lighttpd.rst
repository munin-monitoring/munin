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

 # Use cgi rendering for graph and html
 graph_strategy cgi
 html_strategy cgi

Webserver configuration
=======================

.. index::
   pair: example; lighttpd configuration

::

  alias.url += ( "/munin-static" => "/etc/munin/static" )
  alias.url += ( "/munin"        => "/var/cache/munin/www/" )

  fastcgi.server += ("/munin-cgi/munin-cgi-graph" =>
                     (( "socket"      => "/var/run/lighttpd/munin-cgi-graph.sock",
                        "bin-path"    => "/usr/lib/munin/cgi/munin-cgi-graph",
                        "check-local" => "disable",
                     )),
                    "/munin-cgi/munin-cgi-html" =>
                     (( "socket"      => "/var/run/lighttpd/munin-cgi-html.sock",
                        "bin-path"    => "/usr/lib/munin/cgi/munin-cgi-html",
                        "check-local" => "disable",
                     ))
                   )

  url.rewrite-repeat += (
                     "/munin/(.*)" => "/munin-cgi/munin-cgi-html/$1",
                     "/munin-cgi/munin-cgi-html$" => "/munin-cgi/munin-cgi-html/",
                     "/munin-cgi/munin-cgi-html/static/(.*)" => "/munin-static/$1"
                     )
