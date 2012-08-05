.. _example-webserver-nginx:

=====================
 nginx configuration
=====================

This example describes how to set up munin on nginx.

nginx does not spawn FastCGI processes by itself, but comes with an
external "spawn-fcgi" program.

We need one process for the graph rendering, and one for the html
generation.

Munin configuration
===================

This example assumes the following configuration in
/etc/munin/munin.conf

.. index::
   pair: example; munin.conf

::

 # graph_strategy should be commented out, if present
 html_strategy cgi

FastCGI configuration
=====================

This will spawn two FastCGI processes trees. One for munin cgi
graphing and one for HTML generation. It will create a socket owned by
www-data, and run the processes as the "munin" user.

.. index::
   pair: example; munin-cgi-graph invocation

.. code-block:: bash

  spawn-fcgi -s /var/run/munin/fastcgi-graph.sock -U www-data \
    -u munin -g munin /usr/lib/cgi-bin/munin-cgi-graph

  spawn-fcgi -s /var/run/munin/fastcgi-html.sock  -U www-data \
    -u munin -g munin /usr/lib/cgi-bin/munin-html-graph

Note: Depending on your installation method, the "munin-\*-graph"
programs may be in another directory. Check Makefile.config if you
installed from source, or your package manager if you used that to
install.

Note: If you installed using the package manager on Debian or Ubuntu,
the /var/log/munin/munin-cgi-\*.log files may be owned by the
"www-data" user. This example runs the processes as the "munin" user,
so you need to chown the log files, and edit /etc/logrotate.d/munin.

Webserver configuration
=======================

.. index::
   pair: example; lighttpd configuration

::

    location ^~ /cgi-bin/munin-cgi-graph/ {
        fastcgi_split_path_info ^(/cgi-bin/munin-cgi-graph)(.*);
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/munin/fastcgi-graph.sock;
        include fastcgi_params;
    }

    location /munin/static/ {
        alias /etc/munin/static/;
    }

    location /munin/ {
        fastcgi_split_path_info ^(/munin)(.*);
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/munin/fastcgi-html.sock;
        include fastcgi_params;
    }
