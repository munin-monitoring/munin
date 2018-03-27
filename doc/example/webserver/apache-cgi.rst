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

        Alias /munin/static/ /etc/munin/static/
        <Directory /etc/munin/static>
            Require all granted
        </Directory>

        ScriptAlias /munin-cgi/munin-cgi-graph /usr/lib/munin/cgi/munin-cgi-graph
        ScriptAlias /munin /usr/lib/munin/cgi/munin-cgi-html
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
