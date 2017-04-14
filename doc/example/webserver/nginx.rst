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
    -u munin -g munin /usr/lib/munin/cgi/munin-cgi-graph

  spawn-fcgi -s /var/run/munin/fastcgi-html.sock  -U www-data \
    -u munin -g munin /usr/lib/munin/cgi/munin-cgi-html

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
   pair: example; nginx configuration

::

    location ^~ /munin-cgi/munin-cgi-graph/ {
        fastcgi_split_path_info ^(/munin-cgi/munin-cgi-graph)(.*);
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

Authentication and group access
===============================

.. index::
   pair: example; nginx authentication group configuration

If you have munin statistics, and need to allow some user (ie:
customers) to access only graphs for a subset of nodes, the easiest way
might be to use groups, and authentication with the exact same name as
the node-group name.

Here is an example of how to redirect the users to the group that
matches their name, and prevent any access to other groups. It also has
allow an admin user to see it all.

Warning: If you don't want users to get any information about the other
group names, you should also change the templates accordingly, and
remove any navigation part that might.

::

    # Here, the whole vhost has auth requirements.
    # You can duplicate it to the graph and html locations if you have
    # something else that doesn't need auth.
    auth_basic            "Restricted stats";
    auth_basic_user_file  /some/path/to/.htpasswd;

    location ^~ /cgi-bin/munin-cgi-graph/ {
        # not authenticated => no rewrite (back to auth)
        if ($remote_user ~ ^$) { break; }

       # is on the right subtree ?
        set $ok "no";
        # admin can see it all
        if ($remote_user = 'admin') { set $ok "yes"; }
        # only allow given path
        if ($uri ~ /cgi-bin/munin-cgi-graph/([^/]*)) { set $path $1; }
        if ($path = $remote_user) { set $ok "yes"; }

        # not allowed here ? redirect them where they should land
        if ($ok != "yes") {
            # redirect to where they should be
            rewrite / /cgi-bin/munin-cgi-graph/$remote_user/ redirect;
        }

        fastcgi_split_path_info ^(/cgi-bin/munin-cgi-graph)(.*);
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/munin/fastcgi-graph.sock;
        include fastcgi_params;
    }

    location /munin/static/ {
        alias /etc/munin/static/;
    }

    location /munin/ {
        # not authenticated => no rewrite (back to auth)
        if ($remote_user ~ ^$) { break; }

       # is on the right subtree ?
        set $ok "no";
        # admin can see it all
        if ($remote_user = 'admin') { set $ok "yes"; }
        # only allow given path
        if ($uri ~ /munin/([^/]*)) { set $path $1; }
        if ($path = $remote_user) { set $ok "yes"; }

        # not allowed here ? redirect them where they should land
        if ($ok != "yes") {
            # redirect to where they should be
            rewrite / /munin/$remote_user/ redirect;
        }

        fastcgi_split_path_info ^(/munin)(.*);
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass unix:/var/run/munin/fastcgi-html.sock;
        include fastcgi_params;
    }
