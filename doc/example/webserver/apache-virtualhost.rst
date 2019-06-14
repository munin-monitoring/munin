.. _example-webserver-apache:

==================================
 Apache virtualhost configuration
==================================

This example describes how to set up munin on a separate apache httpd
virtual host. It uses FastCGI if this is available, and falls back to
CGI if it is not.

Munin configuration
===================

This example assumes the following configuration in
/etc/munin/munin.conf

.. index::
   pair: example; munin.conf

::

 graph_strategy cgi
 html_strategy  cgi

Virtualhost configuration
=========================

Add a new virtualhost, using the following example:

.. index::
   pair: example; apache httpd configuration

::

 <VirtualHost *:80>
     ServerName munin.example.org
     ServerAlias munin

     ServerAdmin  info@example.org

     DocumentRoot /srv/www/munin.example.org

     ErrorLog  /var/log/apache2/munin.example.org-error.log
     CustomLog /var/log/apache2/munin.example.org-access.log combined

     # Rewrites
     RewriteEngine On

     # Static content in /static
     RewriteRule ^/favicon.ico /etc/munin/static/favicon.ico [L]
     RewriteRule ^/static/(.*) /etc/munin/static/$1          [L]

     # HTML
     RewriteCond %{REQUEST_URI} .html$ [or]
     RewriteCond %{REQUEST_URI} =/
     RewriteRule ^/(.*)          /usr/lib/munin/cgi/munin-cgi-html/$1 [L]

     # Images
     RewriteRule ^/munin-cgi/munin-cgi-graph/(.*) /usr/lib/munin/cgi/munin-cgi-graph/$1 [L]

     # Ensure we can run (fast)cgi scripts
     <Directory "/usr/lib/munin/cgi">
         Options +ExecCGI
         <IfModule mod_fcgid.c>
             SetHandler fcgid-script
         </IfModule>
         <IfModule !mod_fcgid.c>
             SetHandler cgi-script
         </IfModule>
     </Directory>
 </VirtualHost>
