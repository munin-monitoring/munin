=======================
 Initial configuration
=======================

Node
====

Plugins
-------

Decide which plugins to use. The munin node runs all plugins present
in CONFDIR/plugins/

The quick auto-plug-and-play solution:

.. code-block:: bash

 munin-node-configure --shell --families=contrib,auto | sh -x

Access
------

The munin node listens on all interfaces by default, but has a
restrictive access list. You need to add your master's IP address.

The "cidr_allow", "cidr_deny", "allow" and "deny" statements are used.

cidr_allow uses the following syntax (the /32 is not implicit, so for
a single host, you need to add it):

    | cidr_allow 127.0.0.0/8
    | cidr_allow 192.0.2.1/32

allow uses regular expression matching against the client IP address.

    | allow '^127\.'
    | allow '^192\.0\.2\.1$'

For specific information about the syntax, see `Net::Server
<http://search.cpan.org/dist/Net-Server/lib/Net/Server.pod>`_. Please
keep in mind that cidr_allow is a recent addition, and may not be
available on all systems.

Startup
-------

Start the node agent (as root) SBINDIR/munin-node. Restart it it it
was already started. The node only discovers new plugins when it is
restarted.

You probably want to use an init-script instead and you might find a
good one under build/dists or in the build/resources directory (maybe
you need to edit the init script, check the given paths in the script
you might use).

Master
======

Add some nodes
--------------

Add some nodes to CONFDIR/munin.conf

[node.example.com]
  address 192.0.2.4

[node2.example.com]
  address node2.example.com

[node3.example.com]
  address 2001:db8::de:caf:bad

Configure web server
====================

On the master, you need to configure your web server.

To generate graphs and html dynamically, you need the following
configuration:

Add the following to CONFDIR/munin.conf

    | html_strategy cgi
    | graph_strategy cgi

Apache HTTPD
------------

Add a new virtualhost, using the following example:


    | <VirtualHost \*:80>
    |     ServerName munin.example.org
    |     ServerAlias munin
    |
    |     ServerAdmin  info@example.org
    |
    |     DocumentRoot /srv/www/munin.example.org
    |
    |     ErrorLog     /var/log/apache2/munin.example.org-error.log
    |     CustomLog    /var/log/apache2/munin.example.org-access.log combined
    |
    |     ServerSignature Off
    |
    |     Alias /static /etc/munin/static
    |
    |     # Rewrites
    |     RewriteEngine On
    |
    |     # HTML
    |     RewriteCond %{REQUEST_URI} !^/static
    |     RewriteCond %{REQUEST_URI} .html$ [or]
    |     RewriteCond %{REQUEST_URI} =/
    |     RewriteRule ^/(.*)          /usr/lib/cgi-bin/munin-cgi-html/$1 [L]
    |
    |     # Images
    |
    |     # - remove path to munin-cgi-graph, if present
    |     RewriteRule ^/cgi-bin/munin-cgi-graph/(.*) /$1
    |
    |     RewriteCond %{REQUEST_URI}                 !^/static
    |     RewriteCond %{REQUEST_URI}                 .png$
    |     RewriteRule ^/(.*) /usr/lib/cgi-bin/munin-cgi-graph/$1 [L]
    |
    |     # Ensure we can run (fast)cgi scripts
    |     <Directory "/usr/lib/cgi-bin">
    |   Options +ExecCGI
    |   <IfModule mod_fcgid.c>
    |       SetHandler fcgid-script
    |   </IfModule>
    |   <IfModule !mod_fcgid.c>
    |       SetHandler cgi-script
    |   </IfModule>
    |     </Directory>
    |
    | </VirtualHost>
