.. _example-webserver-apache-cgi:

============================
 Apache CGI Configuration
============================

This example describes how to generate graphs and HTML files dynamically (on demand) via
`Apache <https://httpd.apache.org/>`_.


Virtualhost configuration
=========================

Add a new virtualhost, using the following example:

.. index::
   triple: munin-cgi; apache configuration; example

::

    <VirtualHost *:80>
        ServerName munin.example.org
        ServerAlias munin

        ServerAdmin  info@example.org

        DocumentRoot /var/www

        # Rewrite rules to serve traffic from the root instead of /munin-cgi
        RewriteEngine On
        # Static files
        RewriteRule ^/favicon.ico /var/cache/munin/www/static/favicon.ico [L]
        RewriteRule ^/static/(.*) /var/cache/munin/www/static/$1          [L]
        # HTML
        RewriteRule ^(/.*\.html)?$ /munin-cgi/munin-cgi-html/$1 [PT]
        # Images
        RewriteRule ^/munin-cgi/munin-cgi-graph/(.*) /$1
        RewriteCond %{REQUEST_URI} !^/static
        RewriteRule ^/(.*.png)$ /munin-cgi/munin-cgi-graph/$1 [L,PT]

        ScriptAlias /munin-cgi/munin-cgi-graph /usr/lib/munin/cgi/munin-cgi-graph
        ScriptAlias /munin-cgi/munin-cgi-html /usr/lib/munin/cgi/munin-cgi-html

        <Directory /etc/munin/static>
            Require all granted
        </Directory>

        <Directory /usr/lib/munin/cgi>
            Require all granted
            <IfModule mod_fcgid.c>
                SetHandler fcgid-script
            </IfModule>
            <IfModule !mod_fcgid.c>
                SetHandler cgi-script
            </IfModule>
        </Directory>

        CustomLog /var/log/apache2/munin.example.org-access.log combined
        ErrorLog  /var/log/apache2/munin.example.org-error.log
    </VirtualHost>
